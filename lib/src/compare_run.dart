part of 'compare_command.dart';

const _encoder = JsonEncoder.withIndent('  ');

/// One run of the compare command over an extracted log: it collapses the
/// samples, gates each scenario, records history and writes the reports,
/// remembering whether anything failed.
class _CompareRun {
  _CompareRun(this.options, {required this.out, required this.err});

  final _CompareOptions options;
  final IOSink out;
  final IOSink err;
  var _failed = false;

  /// Runs every gate over [extraction] and returns whether the run passed.
  bool execute(PerfLogExtraction extraction) {
    final grouped = <String, List<PerfSummary>>{};
    for (final s in extraction.summaries) {
      grouped.putIfAbsent(s.scenario, () => []).add(s);
    }
    if (!options.update) {
      // A marked line that did not parse is a scenario whose result is
      // unknown, so it cannot count as a pass.
      if (extraction.errors.isNotEmpty) _failed = true;
      if (!options.allowMissing) _failOnMissingScenarios(grouped.keys);
    }
    final medians = _collapseSamples(grouped);

    // Read the history *before* recording this run, so a scenario is never
    // measured against a reference window that already includes itself.
    final history = _readHistory();
    final reports = [for (final m in medians) _gate(m, history)];
    _appendHistory(medians);
    _writeReports(reports);

    if (options.failOnDrift && reports.any((r) => r.drift?.drifted ?? false)) {
      _failed = true;
    }
    _failOnGrades(reports);
    return !_failed;
  }

  /// Fails for every baseline whose scenario is not among [present].
  ///
  /// A scenario that silently stopped running — a deleted test, a renamed
  /// scenario, a crash before it reported — would otherwise pass the gate
  /// forever, because only scenarios in the log are compared.
  void _failOnMissingScenarios(Iterable<String> present) {
    final dir = Directory(options.baselineDir);
    if (!dir.existsSync()) return;
    // Case-folded, as a case-insensitive file system resolves the baseline.
    final seen = {for (final name in present) name.toLowerCase()};
    const suffix = '.perf.json';
    final missing = [
      for (final file in dir.listSync().whereType<File>())
        if (file.uri.pathSegments.last case final name
            when name.endsWith(suffix))
          name.substring(0, name.length - suffix.length),
    ].where((name) => !seen.contains(name.toLowerCase())).toList()
      ..sort();
    for (final name in missing) {
      err.writeln(
        'Missing scenario "$name": ${options.baselineDir}/$name$suffix has no '
        'summary in this log. Delete the baseline if the scenario is gone, or '
        'pass --allow-missing to compare only what ran.',
      );
      _failed = true;
    }
  }

  /// Collapses each scenario's samples to a per-metric median, refusing the
  /// scenarios that cannot be gated.
  ///
  /// A scenario measured several times in one run contributes several log
  /// lines; single captures are noisy enough that comparing one run against
  /// one baseline false-alarms on unchanged code. Refused scenarios are left
  /// out here, so they never reach the baselines or the history.
  List<PerfSummary> _collapseSamples(Map<String, List<PerfSummary>> grouped) {
    final clashing = _caseClashes(grouped.keys);
    final medians = <PerfSummary>[];
    for (final MapEntry(key: name, value: samples) in grouped.entries) {
      final refusal = _refusal(name, samples, clashing[name]);
      if (refusal != null) {
        err.writeln('Refusing scenario "$name": $refusal');
        _failed = true;
        continue;
      }
      medians.add(PerfSummary.medianOf(samples));
      if (samples.length > 1) {
        out.writeln('Using median of ${samples.length} samples for "$name".');
      }
    }
    return medians;
  }

  /// Why scenario [name] cannot be gated, or null if it can. [twins] are the
  /// other scenario names that differ from it only by case.
  String? _refusal(
    String name,
    List<PerfSummary> samples,
    List<String>? twins,
  ) {
    // The name becomes a file name, so `../x` would write outside
    // --baseline-dir under --update.
    if (!_isSafeScenarioName(name)) {
      return 'a scenario name is used as a file name, so it must not be empty '
          'or contain a path separator or "..".';
    }
    if (twins != null) {
      return 'it differs only by case from '
          '${twins.map((n) => '"$n"').join(', ')}, so on a case-insensitive '
          'file system (macOS, Windows) both would share one baseline file.';
    }
    final budgets = {for (final s in samples) s.frameBudgetMillis};
    if (budgets.any((b) => !sameFrameBudget(b, budgets.first))) {
      return 'its samples were captured at different frame budgets '
          '(${budgets.join('ms, ')}ms), so they come from different displays '
          'and have no meaningful median.';
    }
    return null;
  }

  PerfHistory? _readHistory() {
    final path = options.historyPath;
    if (path == null || !File(path).existsSync()) return null;
    final history = parseHistory(File(path).readAsStringSync());
    history.errors.forEach(err.writeln);
    return history;
  }

  /// Updates or compares one scenario's baseline and returns its report.
  ScenarioReport _gate(PerfSummary current, PerfHistory? history) {
    final drift = history == null
        ? null
        : analyzeDrift(
            history: history.forScenario(current.scenario),
            current: current,
          );
    // An empty capture encodes no performance information but passes every
    // check, so recording one would bake a permanently-green gate into the
    // repo. Refuse it at the point it would be written.
    if (current.sampledFrameCount <= 0) {
      err.writeln(
        'Refusing to use "${current.scenario}": the run captured 0 frames. '
        'The measurement did not happen (widget test instead of '
        'integration_test, or an action that drove no frames).',
      );
      _failed = true;
      return ScenarioReport(summary: current);
    }
    final baselineFile =
        File('${options.baselineDir}/${current.scenario}.perf.json');
    if (options.update) {
      if (current.buildMode == 'debug' && !options.allowDebugBaseline) {
        err.writeln(
          'Refusing to record "${current.scenario}": it was measured in debug '
          'mode, where asserts and JIT dominate frame times. Capture in '
          'profile mode on the pinned device, or pass --allow-debug-baseline '
          'to record it anyway.',
        );
        _failed = true;
        return ScenarioReport(summary: current, drift: drift);
      }
      baselineFile.parent.createSync(recursive: true);
      baselineFile.writeAsStringSync('${_encoder.convert(current.toJson())}\n');
      out.writeln('Updated baseline: ${baselineFile.path}');
      return ScenarioReport(summary: current, drift: drift);
    }
    final baseline = _readBaseline(baselineFile, current.scenario);
    if (baseline == null) {
      _failed = true;
      return ScenarioReport(summary: current, drift: drift);
    }
    final result =
        const PerfComparator().compare(baseline: baseline, current: current);
    _printComparison(result);
    _warnOnBuildModes(baseline: baseline, current: current);
    if (!result.passed) _failed = true;
    return ScenarioReport(summary: current, comparison: result, drift: drift);
  }

  /// Reads a committed baseline, or reports why it could not be read and
  /// returns null. A corrupt golden fails the gate with its path rather than
  /// a stack trace.
  PerfSummary? _readBaseline(File file, String scenario) {
    if (!file.existsSync()) {
      err.writeln(
        'No baseline for "$scenario". '
        'Run with --update to create ${file.path}.',
      );
      return null;
    }
    try {
      return PerfSummary.fromJson(decodeJsonObject(file.readAsStringSync()));
    } on FormatException catch (e) {
      err.writeln('Unreadable baseline ${file.path}: ${e.message}');
      return null;
    }
  }

  /// Flags a comparison whose numbers are not meaningful because of the build
  /// mode they were measured in. Advisory: the verdict is left as it is.
  void _warnOnBuildModes({
    required PerfSummary baseline,
    required PerfSummary current,
  }) {
    if (current.buildMode == 'debug') {
      out.writeln(
        '  !    measured in debug mode; frame times are not representative',
      );
    }
    final (was, now) = (baseline.buildMode, current.buildMode);
    if (was != null && now != null && was != now) {
      out.writeln(
        '  !    baseline was measured in $was mode, this run in $now',
      );
    }
  }

  void _printComparison(PerfComparison result) {
    out.writeln('\n[${result.passed ? 'PASS' : 'FAIL'}] ${result.scenario}');
    for (final c in result.checks) {
      out.writeln('  ${_formatCheck(c)}');
    }
    for (final e in result.errors) {
      out.writeln('  ERR  $e');
    }
    for (final w in result.warnings) {
      out.writeln('  !    $w');
    }
  }

  /// Appends this run to the history, after analysis, so it becomes part of
  /// the record for next time without influencing its own verdict.
  ///
  /// Empty captures are left out: recording a dead run would poison the trend.
  void _appendHistory(List<PerfSummary> medians) {
    final path = options.historyPath;
    if (path == null) return;
    // UTC, so a history shared by CI and laptops in other time zones records
    // one unambiguous instant per run.
    final now = DateTime.now().toUtc();
    final entries = [
      for (final s in medians)
        if (s.sampledFrameCount > 0)
          PerfHistoryEntry(recordedAt: now, summary: s, label: options.label),
    ];
    if (entries.isEmpty) return;
    final file = File(path)..parent.createSync(recursive: true);
    file.writeAsStringSync(
      '${_needsLeadingNewline(file) ? '\n' : ''}'
      '${encodeHistoryEntries(entries)}',
      mode: FileMode.append,
    );
    out.writeln('Recorded ${entries.length} run(s) to ${file.path}.');
  }

  void _writeReports(List<ScenarioReport> reports) {
    final sink = out;
    final colored = sink is Stdout &&
        sink.supportsAnsiEscapes &&
        (Platform.environment['NO_COLOR'] ?? '').isEmpty;
    out.writeln(renderTerminalSummary(reports, colored: colored));

    final path = options.reportPath;
    if (path == null) return;
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        renderHtmlReport(reports, generatedAt: DateTime.now().toUtc()),
      );
    out.writeln('Wrote HTML report: $path');
  }

  /// Fails every scenario graded at or below `--fail-on-grade`.
  ///
  /// An absolute backstop, independent of any baseline: a screen whose p90
  /// exceeds the frame budget is janky on the device that measured it,
  /// whatever its baseline says. Catches a baseline recorded from an
  /// already-slow screen, which every later run dutifully "passes".
  void _failOnGrades(List<ScenarioReport> reports) {
    final limit = options.gradeLimit;
    if (limit == null) return;
    for (final r in reports) {
      if (r.grade.severity < limit.severity) continue;
      err.writeln(
        '"${r.summary.scenario}" grades ${r.grade.name}, at or below the '
        '--fail-on-grade=${limit.name} threshold.',
      );
      _failed = true;
    }
  }
}
