// dart format off
import 'dart:convert' show JsonEncoder, jsonDecode;
import 'dart:io' show File, FileMode, Platform, exit, stderr, stdout;

// Import the pure-Dart sources directly rather than the barrel: the barrel
// re-exports measure_screen_performance.dart, which pulls in Flutter/dart:ui and
// would prevent this CLI from running under the standalone Dart VM.
import 'package:frame_baseline/src/perf_comparator.dart'
    show PerfCheck, PerfComparator, PerfComparison;
import 'package:frame_baseline/src/perf_history.dart'
    show PerfHistoryEntry, encodeHistoryEntries, parseHistory;
import 'package:frame_baseline/src/perf_report.dart'
    show ScenarioReport, renderHtmlReport, renderTerminalSummary;
import 'package:frame_baseline/src/perf_reporter.dart'
    show extractPerfSummaries, kPerfSummaryMarker;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
import 'package:frame_baseline/src/perf_trend.dart'
    show PerfDrift, analyzeDrift;
// dart format on

/// Host-side gate: extracts on-device [PerfSummary] JSON from a device/CI log,
/// then either compares each scenario against its committed golden baseline or
/// (with `--update`) rewrites those baselines.
///
/// ```
/// dart run frame_baseline:compare <log> \
///     [--baseline-dir=DIR] [--update] [--report=FILE.html] \
///     [--history=FILE.jsonl] [--label=SHA] [--fail-on-drift]
/// ```
///
/// Exit code is non-zero if any scenario regressed or a baseline is missing,
/// so it works directly as a CI gate. `--report` writes a color-coded HTML
/// overview of every screen (works in `--update` mode too, for an at-a-glance
/// view even before baselines exist).
///
/// `--history` appends each run to an append-only JSONL log and reports how far
/// each scenario has drifted since that history began — the slow-creep case a
/// single baseline comparison structurally cannot catch.
const _defaultBaselineDir = 'perf/baselines';
const _encoder = JsonEncoder.withIndent('  ');

void main(List<String> args) {
  final update = args.contains('--update');
  final failOnDrift = args.contains('--fail-on-drift');
  final baselineDir =
      _optionValue(args, '--baseline-dir') ?? _defaultBaselineDir;
  final reportPath = _optionValue(args, '--report');
  final historyPath = _optionValue(args, '--history');
  final label = _optionValue(args, '--label');
  final positional = args.where((a) => !a.startsWith('--')).toList();

  if (positional.isEmpty) {
    stderr.writeln(
      'Usage: dart run frame_baseline:compare '
      '<device-log-file> [--baseline-dir=DIR] [--update] [--report=FILE.html] '
      '[--history=FILE.jsonl] [--label=SHA] [--fail-on-drift]',
    );
    exit(64);
  }

  if (failOnDrift && historyPath == null) {
    stderr.writeln('--fail-on-drift requires --history=FILE.jsonl.');
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
  final medians = [
    for (final entry in grouped.entries) PerfSummary.medianOf(entry.value),
  ];
  for (final entry in grouped.entries) {
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

  var failed = false;
  var drifted = false;
  const comparator = PerfComparator();
  final reports = <ScenarioReport>[];

  for (final current in medians) {
    final baselineFile = File('$baselineDir/${current.scenario}.perf.json');

    final PerfDrift? drift = history == null
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

    final baseline = PerfSummary.fromJson(
      jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>,
    );
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
    final now = DateTime.now();
    final entries = [
      for (final s in medians)
        if (s.sampledFrameCount > 0)
          PerfHistoryEntry(recordedAt: now, summary: s, label: label),
    ];
    if (entries.isNotEmpty) {
      historyFile.parent.createSync(recursive: true);
      historyFile.writeAsStringSync(
        encodeHistoryEntries(entries),
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
        generatedAtIso: DateTime.now().toIso8601String(),
      ),
    );
    stdout.writeln('Wrote HTML report: ${reportFile.path}');
  }

  if (drifted && failOnDrift) failed = true;

  exit(failed ? 1 : 0);
}

String? _optionValue(List<String> args, String name) {
  final prefix = '$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
  }
  return null;
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
