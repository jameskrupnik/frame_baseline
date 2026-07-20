// dart format off
import 'dart:convert' show JsonEncoder, jsonDecode;
import 'dart:io' show File, exit, stderr, stdout;

// Import the pure-Dart sources directly rather than the barrel: the barrel
// re-exports measure_screen_performance.dart, which pulls in Flutter/dart:ui and
// would prevent this CLI from running under the standalone Dart VM.
import 'package:frame_baseline/src/perf_comparator.dart'
    show PerfCheck, PerfComparator, PerfComparison;
import 'package:frame_baseline/src/perf_reporter.dart' show kPerfSummaryMarker;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// Host-side gate: extracts on-device [PerfSummary] JSON from a device/CI log,
/// then either compares each scenario against its committed golden baseline or
/// (with `--update`) rewrites those baselines.
///
/// `dart run frame_baseline:compare <log> [--baseline-dir=DIR] [--update]`
///
/// Exit code is non-zero if any scenario regressed or a baseline is missing,
/// so it works directly as a CI gate.
const _defaultBaselineDir = 'perf/baselines';
const _encoder = JsonEncoder.withIndent('  ');

void main(List<String> args) {
  final update = args.contains('--update');
  final baselineDir =
      _optionValue(args, '--baseline-dir') ?? _defaultBaselineDir;
  final positional = args.where((a) => !a.startsWith('--')).toList();

  if (positional.isEmpty) {
    stderr.writeln(
      'Usage: dart run frame_baseline:compare '
      '<device-log-file> [--baseline-dir=DIR] [--update]',
    );
    exit(64);
  }

  final logFile = File(positional.first);
  if (!logFile.existsSync()) {
    stderr.writeln('Log file not found: ${positional.first}');
    exit(66);
  }

  final summaries = _extractSummaries(logFile.readAsStringSync());
  if (summaries.isEmpty) {
    stderr.writeln(
      'No perf summaries found in ${logFile.path} '
      '(expected lines containing "$kPerfSummaryMarker").',
    );
    exit(1);
  }

  var failed = false;
  const comparator = PerfComparator();

  for (final current in summaries) {
    final baselineFile = File('$baselineDir/${current.scenario}.perf.json');

    if (update) {
      baselineFile.parent.createSync(recursive: true);
      baselineFile.writeAsStringSync('${_encoder.convert(current.toJson())}\n');
      stdout.writeln('Updated baseline: ${baselineFile.path}');
      continue;
    }

    if (!baselineFile.existsSync()) {
      stderr.writeln(
        'No baseline for "${current.scenario}". '
        'Run with --update to create ${baselineFile.path}.',
      );
      failed = true;
      continue;
    }

    final baseline = PerfSummary.fromJson(
      jsonDecode(baselineFile.readAsStringSync()) as Map<String, dynamic>,
    );
    final result = comparator.compare(baseline: baseline, current: current);
    _printReport(result);
    if (!result.passed) failed = true;
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

List<PerfSummary> _extractSummaries(String log) {
  final summaries = <PerfSummary>[];
  for (final line in log.split('\n')) {
    final idx = line.indexOf(kPerfSummaryMarker);
    if (idx == -1) continue;
    final jsonStr = line.substring(idx + kPerfSummaryMarker.length).trim();
    try {
      summaries.add(
        PerfSummary.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>),
      );
    } catch (e) {
      stderr.writeln('Skipping unparsable perf line: $e');
    }
  }
  return summaries;
}

void _printReport(PerfComparison result) {
  final status = result.passed ? 'PASS' : 'FAIL';
  stdout.writeln('\n[$status] ${result.scenario}');
  for (final c in result.checks) {
    stdout.writeln('  ${_formatCheck(c)}');
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
