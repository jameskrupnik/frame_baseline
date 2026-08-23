// dart format off
import 'dart:convert' show JsonEncoder, jsonDecode;
import 'dart:io' show File, Platform, exit, stderr, stdout;

// Import the pure-Dart sources directly rather than the barrel: the barrel
// re-exports measure_screen_performance.dart, which pulls in Flutter/dart:ui and
// would prevent this CLI from running under the standalone Dart VM.
import 'package:frame_baseline/src/perf_comparator.dart'
    show PerfCheck, PerfComparator, PerfComparison;
import 'package:frame_baseline/src/perf_report.dart'
    show ScenarioReport, renderHtmlReport, renderTerminalSummary;
import 'package:frame_baseline/src/perf_reporter.dart'
    show extractPerfSummaries, kPerfSummaryMarker;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// Host-side gate: extracts on-device [PerfSummary] JSON from a device/CI log,
/// then either compares each scenario against its committed golden baseline or
/// (with `--update`) rewrites those baselines.
///
/// ```
/// dart run frame_baseline:compare <log> \
///     [--baseline-dir=DIR] [--update] [--report=FILE.html]
/// ```
///
/// Exit code is non-zero if any scenario regressed or a baseline is missing,
/// so it works directly as a CI gate. `--report` writes a color-coded HTML
/// overview of every screen (works in `--update` mode too, for an at-a-glance
/// view even before baselines exist).
const _defaultBaselineDir = 'perf/baselines';
const _encoder = JsonEncoder.withIndent('  ');

void main(List<String> args) {
  final update = args.contains('--update');
  final baselineDir =
      _optionValue(args, '--baseline-dir') ?? _defaultBaselineDir;
  final reportPath = _optionValue(args, '--report');
  final positional = args.where((a) => !a.startsWith('--')).toList();

  if (positional.isEmpty) {
    stderr.writeln(
      'Usage: dart run frame_baseline:compare '
      '<device-log-file> [--baseline-dir=DIR] [--update] [--report=FILE.html]',
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

  var failed = false;
  const comparator = PerfComparator();
  final reports = <ScenarioReport>[];

  for (final current in medians) {
    final baselineFile = File('$baselineDir/${current.scenario}.perf.json');

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
      reports.add(ScenarioReport(summary: current));
      continue;
    }

    if (!baselineFile.existsSync()) {
      stderr.writeln(
        'No baseline for "${current.scenario}". '
        'Run with --update to create ${baselineFile.path}.',
      );
      failed = true;
      reports.add(ScenarioReport(summary: current));
      continue;
    }

    final baseline = PerfSummary.fromJson(
      jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>,
    );
    final result = comparator.compare(baseline: baseline, current: current);
    _printReport(result);
    reports.add(ScenarioReport(summary: current, comparison: result));
    if (!result.passed) failed = true;
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
