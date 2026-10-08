// dart format off
import 'dart:convert' show JsonEncoder;
import 'dart:io' show File, FileMode, Platform, exit, stderr, stdout;

// Import the pure-Dart sources directly rather than the barrel: the barrel
// re-exports measure_screen_performance.dart, which pulls in Flutter/dart:ui and
// would prevent this CLI from running under the standalone Dart VM.
import 'package:frame_baseline/src/json_fields.dart' show decodeJsonObject;
import 'package:frame_baseline/src/perf_comparator.dart'
    show PerfCheck, PerfComparator, PerfComparison;
import 'package:frame_baseline/src/perf_history.dart'
    show PerfHistoryEntry, encodeHistoryEntries, parseHistory;
import 'package:frame_baseline/src/perf_report.dart'
    show PerfGrade, ScenarioReport, renderHtmlReport, renderTerminalSummary;
import 'package:frame_baseline/src/perf_reporter.dart'
    show extractPerfSummaries, kPerfSummaryMarker;
import 'package:frame_baseline/src/perf_summary.dart'
    show PerfSummary, sameFrameBudget;
import 'package:frame_baseline/src/perf_trend.dart' show analyzeDrift;
// dart format on

const _defaultBaselineDir = 'perf/baselines';
const _encoder = JsonEncoder.withIndent('  ');

const _usage = 'Usage: dart run frame_baseline:compare '
    '<device-log-file> [--baseline-dir=DIR] [--update] [--report=FILE.html] '
    '[--history=FILE.jsonl] [--label=SHA] [--fail-on-drift] '
    '[--fail-on-grade=good|ok|poor]';

/// Options that are switched on by their presence alone.
const _flags = {'--update', '--fail-on-drift'};

/// Options that take a value, written as `--name=value`.
const _valuedOptions = {
  '--baseline-dir',
  '--report',
  '--history',
  '--label',
  '--fail-on-grade',
};

/// Host-side gate: extracts on-device [PerfSummary] JSON from a device/CI log,
/// then either compares each scenario against its committed golden baseline or
/// (with `--update`) rewrites those baselines.
///
/// ```sh
/// dart run frame_baseline:compare <log> \
///     [--baseline-dir=DIR] [--update] [--report=FILE.html] \
///     [--history=FILE.jsonl] [--label=SHA] [--fail-on-drift] \
///     [--fail-on-grade=poor]
/// ```
///
/// Exit code is non-zero if any scenario regressed, a baseline is missing or
/// unreadable, or the arguments are malformed, so it works directly as a CI
/// gate. `--report` writes a color-coded HTML overview of every screen (works
/// in `--update` mode too, for an at-a-glance view even before baselines
/// exist).
///
/// `--history` appends each run to an append-only JSONL log and reports how far
/// each scenario has drifted since that history began — the slow-creep case a
/// single baseline comparison structurally cannot catch.
void main(List<String> args) {
  _exitOnHelpOrUsageError(args);

  final update = args.contains('--update');
  final failOnDrift = args.contains('--fail-on-drift');
  final baselineDir =
      _optionValue(args, '--baseline-dir') ?? _defaultBaselineDir;
  final reportPath = _optionValue(args, '--report');
  final historyPath = _optionValue(args, '--history');
  final label = _optionValue(args, '--label');
  final positional = args.where((a) => !a.startsWith('-')).toList();

  if (positional.isEmpty) {
    stderr.writeln(_usage);
    exit(64);
  }

  if (failOnDrift && historyPath == null) {
    stderr.writeln('--fail-on-drift requires --history=FILE.jsonl.');
    exit(64);
  }

  final gradeLimitName = _optionValue(args, '--fail-on-grade');
  final gradeLimit =
      gradeLimitName == null ? null : PerfGrade.tryParse(gradeLimitName);
  if (gradeLimitName != null && gradeLimit == null) {
    stderr.writeln(
      'Unknown --fail-on-grade value "$gradeLimitName" '
      '(expected one of: good, ok, poor).',
    );
    exit(64);
  }

  final logFile = File(positional.first);
  if (!logFile.existsSync()) {
    stderr.writeln('Log file not found: ${positional.first}');
    exit(66);
  }

  final extraction = extractPerfSummaries(logFile.readAsStringSync());
  extraction.errors.forEach(stderr.writeln);
  final summaries = extraction.summaries;
  if (summaries.isEmpty) {
    stderr.writeln(
      'No perf summaries found in ${logFile.path} '
      '(expected lines containing "$kPerfSummaryMarker").',
    );
    exit(1);
  }

  // A scenario measured several times in one run contributes several log
  // lines. Collapse them to a per-metric median: single captures are noisy
  // enough that comparing one run against one baseline false-alarms on
  // unchanged code.
  final grouped = <String, List<PerfSummary>>{};
  for (final s in summaries) {
    grouped.putIfAbsent(s.scenario, () => []).add(s);
  }
  var failed = false;
  final clashing = _caseClashes(grouped.keys);
  final medians = <PerfSummary>[];
  for (final entry in grouped.entries) {
    final twins = clashing[entry.key];
    if (twins != null) {
      stderr.writeln(
        'Refusing scenario "${entry.key}": it differs only by case from '
        '${twins.map((n) => '"$n"').join(', ')}, so on a case-insensitive '
        'file system (macOS, Windows) both would share one baseline file.',
      );
      failed = true;
      continue;
    }
    // Samples from displays with different refresh rates have no median.
    final budgets = {for (final s in entry.value) s.frameBudgetMillis};
    if (budgets.any((b) => !sameFrameBudget(b, budgets.first))) {
      stderr.writeln(
        'Refusing scenario "${entry.key}": its samples were captured at '
        'different frame budgets (${budgets.join('ms, ')}ms), so they come '
        'from different displays and have no meaningful median.',
      );
      failed = true;
      continue;
    }
    medians.add(PerfSummary.medianOf(entry.value));
    if (entry.value.length > 1) {
      stdout.writeln(
        'Using median of ${entry.value.length} samples for "${entry.key}".',
      );
    }
  }

  // Read the history *before* recording this run, so a scenario is never
  // measured against a reference window that already includes itself.
  final historyFile = historyPath == null ? null : File(historyPath);
  final history = historyFile != null && historyFile.existsSync()
      ? parseHistory(historyFile.readAsStringSync())
      : null;
  history?.errors.forEach(stderr.writeln);

  var drifted = false;
  const comparator = PerfComparator();
  final reports = <ScenarioReport>[];

  for (final current in medians) {
    // The scenario name comes from the log and becomes a file name, so a name
    // like `../x` would write outside --baseline-dir under --update.
    if (!_isSafeScenarioName(current.scenario)) {
      stderr.writeln(
        'Refusing scenario "${current.scenario}": a scenario name is used as '
        'a file name, so it must not be empty or contain a path separator or '
        '"..".',
      );
      failed = true;
      continue;
    }
    final baselineFile = File('$baselineDir/${current.scenario}.perf.json');

    final drift = history == null
        ? null
        : analyzeDrift(
            history: history.forScenario(current.scenario),
            current: current,
          );
    if (drift != null && drift.drifted) drifted = true;

    // An empty capture encodes no performance information but passes every
    // check, so recording one would bake a permanently-green gate into the
    // repo. Refuse it at the point it would be written.
    if (current.sampledFrameCount <= 0) {
      stderr.writeln(
        'Refusing to use "${current.scenario}": the run captured 0 frames. '
        'The measurement did not happen (widget test instead of '
        'integration_test, or an action that drove no frames).',
      );
      failed = true;
      reports.add(ScenarioReport(summary: current));
      continue;
    }

    if (update) {
      baselineFile.parent.createSync(recursive: true);
      baselineFile.writeAsStringSync('${_encoder.convert(current.toJson())}\n');
      stdout.writeln('Updated baseline: ${baselineFile.path}');
      reports.add(ScenarioReport(summary: current, drift: drift));
      continue;
    }

    if (!baselineFile.existsSync()) {
      stderr.writeln(
        'No baseline for "${current.scenario}". '
        'Run with --update to create ${baselineFile.path}.',
      );
      failed = true;
      reports.add(ScenarioReport(summary: current, drift: drift));
      continue;
    }

    final baseline = _readBaseline(baselineFile);
    if (baseline == null) {
      failed = true;
      reports.add(ScenarioReport(summary: current, drift: drift));
      continue;
    }
    final result = comparator.compare(baseline: baseline, current: current);
    _printReport(result);
    reports.add(
      ScenarioReport(summary: current, comparison: result, drift: drift),
    );
    if (!result.passed) failed = true;
  }

  // Append after analysis, so this run becomes part of the record for next
  // time without influencing its own verdict. Scenarios whose capture was
  // rejected are excluded — recording a dead run would poison the trend.
  if (historyFile != null) {
    // UTC, so a history shared by CI and laptops in other time zones records
    // one unambiguous instant per run.
    final now = DateTime.now().toUtc();
    final entries = [
      for (final s in medians)
        if (s.sampledFrameCount > 0)
          PerfHistoryEntry(recordedAt: now, summary: s, label: label),
    ];
    if (entries.isNotEmpty) {
      historyFile.parent.createSync(recursive: true);
      historyFile.writeAsStringSync(
        '${_needsLeadingNewline(historyFile) ? '\n' : ''}'
        '${encodeHistoryEntries(entries)}',
        mode: FileMode.append,
      );
      stdout.writeln(
        'Recorded ${entries.length} run(s) to ${historyFile.path}.',
      );
    }
  }

  final colored = stdout.supportsAnsiEscapes &&
      (Platform.environment['NO_COLOR'] ?? '').isEmpty;
  stdout.writeln(renderTerminalSummary(reports, colored: colored));

  if (reportPath != null) {
    final reportFile = File(reportPath);
    reportFile.parent.createSync(recursive: true);
    reportFile.writeAsStringSync(
      renderHtmlReport(
        reports,
        generatedAt: DateTime.now().toUtc(),
      ),
    );
    stdout.writeln('Wrote HTML report: ${reportFile.path}');
  }

  if (drifted && failOnDrift) failed = true;

  // Absolute backstop, independent of any baseline: a screen whose p90 exceeds
  // the frame budget is janky on the device that measured it, whatever the
  // baseline happens to say. Catches the case where a baseline was recorded
  // from an already-slow screen and every later run dutifully "passes".
  if (gradeLimit != null) {
    final threshold = gradeLimit.severity;
    for (final r in reports) {
      if (r.grade.severity >= threshold) {
        stderr.writeln(
          '"${r.summary.scenario}" grades ${r.grade.name}, at or below the '
          '--fail-on-grade=${gradeLimit.name} threshold.',
        );
        failed = true;
      }
    }
  }

  exit(failed ? 1 : 0);
}

String? _optionValue(List<String> args, String name) {
  final prefix = '$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
}

/// Exits 0 after printing usage for `--help`, or 64 for malformed [args].
///
/// A CI gate must not guess. An unrecognised or misspelt option, or
/// `--fail-on-grade poor` written with a space, would otherwise be ignored and
/// silently switch a gate off while the build stays green.
void _exitOnHelpOrUsageError(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(_usage);
    exit(0);
  }
  final usageError = _validateArgs(args);
  if (usageError != null) {
    stderr
      ..writeln(usageError)
      ..writeln(_usage);
    exit(64);
  }
}

/// Returns a message describing the first malformed argument, or null when
/// every argument is a known option or the single log-file path.
String? _validateArgs(List<String> args) {
  var positionalCount = 0;
  for (final arg in args) {
    if (!arg.startsWith('-')) {
      positionalCount++;
      if (positionalCount > 1) {
        return 'Unexpected argument "$arg": only one log file is accepted. '
            'Options that take a value must be written as --name=value.';
      }
      continue;
    }
    final eq = arg.indexOf('=');
    final name = eq == -1 ? arg : arg.substring(0, eq);
    if (_flags.contains(name)) {
      if (eq != -1) return '$name does not take a value.';
      continue;
    }
    if (_valuedOptions.contains(name)) {
      if (eq == -1 || eq == arg.length - 1) {
        return '$name needs a value, written as $name=VALUE.';
      }
      continue;
    }
    return 'Unknown option "$arg".';
  }
  return null;
}

/// Whether [scenario] is safe to use as a baseline file name.
bool _isSafeScenarioName(String scenario) =>
    scenario.isNotEmpty &&
    !scenario.contains('/') &&
    !scenario.contains(r'\') &&
    !scenario.contains('..');

/// Maps each name in [names] that collides with others when case is ignored
/// to those others.
Map<String, List<String>> _caseClashes(Iterable<String> names) {
  final byFolded = <String, List<String>>{};
  for (final name in names) {
    byFolded.putIfAbsent(name.toLowerCase(), () => []).add(name);
  }
  return {
    for (final group in byFolded.values)
      if (group.length > 1)
        for (final name in group) name: [...group]..remove(name),
  };
}

/// Whether [file] has content that does not end in a newline, so an append
/// would be glued onto its last line (a hand edit, or a write cut short).
bool _needsLeadingNewline(File file) {
  if (!file.existsSync()) return false;
  final bytes = file.readAsBytesSync();
  return bytes.isNotEmpty && bytes.last != 0x0A;
}

/// Reads a committed baseline, or reports why it could not be read and
/// returns null. A corrupt golden fails the gate with its path rather than a
/// stack trace.
PerfSummary? _readBaseline(File file) {
  try {
    return PerfSummary.fromJson(decodeJsonObject(file.readAsStringSync()));
  } on FormatException catch (e) {
    stderr.writeln('Unreadable baseline ${file.path}: ${e.message}');
    return null;
  }
}

void _printReport(PerfComparison result) {
  final status = result.passed ? 'PASS' : 'FAIL';
  stdout.writeln('\n[$status] ${result.scenario}');
  for (final c in result.checks) {
    stdout.writeln('  ${_formatCheck(c)}');
  }
  for (final e in result.errors) {
    stdout.writeln('  ERR  $e');
  }
  for (final w in result.warnings) {
    stdout.writeln('  !    $w');
  }
}

String _formatCheck(PerfCheck c) {
  final mark = c.passed ? 'ok  ' : 'FAIL';
  final base = c.baseline.toStringAsFixed(2);
  final cur = c.current.toStringAsFixed(2);
  final lim = c.limit.toStringAsFixed(2);
  return '$mark ${c.name.padRight(24)} '
      'baseline=$base current=$cur limit=$lim';
}
