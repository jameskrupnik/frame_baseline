// dart format off
import 'dart:convert' show JsonEncoder;
import 'dart:io'
    show Directory, File, FileMode, IOSink, Platform, Stdout, stderr, stdout;

// Import the pure-Dart sources directly rather than the barrel: the barrel
// re-exports measure_screen_performance.dart, which pulls in Flutter/dart:ui and
// would prevent this CLI from running under the standalone Dart VM.
import 'package:frame_baseline/src/json_fields.dart' show decodeJsonObject;
import 'package:frame_baseline/src/perf_comparator.dart'
    show PerfCheck, PerfComparator, PerfComparison;
import 'package:frame_baseline/src/perf_history.dart'
    show PerfHistory, PerfHistoryEntry, encodeHistoryEntries, parseHistory;
import 'package:frame_baseline/src/perf_report.dart'
    show PerfGrade, ScenarioReport, renderHtmlReport, renderTerminalSummary;
import 'package:frame_baseline/src/perf_reporter.dart'
    show PerfLogExtraction, extractPerfSummaries, kPerfSummaryMarker;
import 'package:frame_baseline/src/perf_summary.dart'
    show PerfSummary, sameFrameBudget;
import 'package:frame_baseline/src/perf_trend.dart' show analyzeDrift;

part 'compare_options.dart';
part 'compare_run.dart';
// dart format on

const _usage = 'Usage: dart run frame_baseline:compare '
    '<device-log-file> [--baseline-dir=DIR] [--update] '
    '[--allow-debug-baseline] [--allow-missing] '
    '[--report=FILE.html] '
    '[--history=FILE.jsonl] [--label=SHA] [--fail-on-drift] '
    '[--fail-on-grade=good|ok|poor]';

/// Options that are switched on by their presence alone.
const _flags = {
  '--update',
  '--fail-on-drift',
  '--allow-missing',
  '--allow-debug-baseline',
};

/// Options that take a value, written as `--name=value`.
const _valuedOptions = {
  '--baseline-dir',
  '--report',
  '--history',
  '--label',
  '--fail-on-grade',
};

/// Runs the `frame_baseline:compare` command over [args] and returns its exit
/// code.
///
/// Extracts on-device [PerfSummary] JSON from a device/CI log, then either
/// compares each scenario against its committed golden baseline or (with
/// `--update`) rewrites those baselines. Progress and the summary go to [out],
/// problems to [err]; they default to stdout and stderr.
///
/// Returns `0` when every scenario passed, `1` when the gate failed, `64` for
/// a usage error and `66` when the log file does not exist. The README lists
/// every cause of `1`.
int runCompare(List<String> args, {IOSink? out, IOSink? err}) {
  final o = out ?? stdout;
  final e = err ?? stderr;
  if (args.contains('--help') || args.contains('-h')) {
    o.writeln(_usage);
    return 0;
  }
  final usageError = _usageError(args);
  if (usageError != null) {
    e
      ..writeln(usageError)
      ..writeln(_usage);
    return 64;
  }

  final options = _CompareOptions.fromArgs(args);
  final logFile = File(options.logPath);
  if (!logFile.existsSync()) {
    e.writeln('Log file not found: ${options.logPath}');
    return 66;
  }

  final extraction = extractPerfSummaries(logFile.readAsStringSync());
  extraction.errors.forEach(e.writeln);
  if (extraction.summaries.isEmpty) {
    e.writeln(
      'No perf summaries found in ${logFile.path} '
      '(expected lines containing "$kPerfSummaryMarker").',
    );
    return 1;
  }
  return _CompareRun(options, out: o, err: e).execute(extraction) ? 0 : 1;
}

/// Returns a message describing why [args] cannot be run, or null.
///
/// A CI gate must not guess. An unrecognised or misspelt option, or
/// `--fail-on-grade poor` written with a space, would otherwise be ignored and
/// silently switch a gate off while the build stays green.
String? _usageError(List<String> args) {
  final malformed = _validateArgs(args);
  if (malformed != null) return malformed;
  if (!args.any((a) => !a.startsWith('-'))) {
    return 'Missing the device log file.';
  }
  if (args.contains('--fail-on-drift') &&
      _optionValue(args, '--history') == null) {
    return '--fail-on-drift requires --history=FILE.jsonl.';
  }
  final grade = _optionValue(args, '--fail-on-grade');
  if (grade != null && PerfGrade.tryParse(grade) == null) {
    return 'Unknown --fail-on-grade value "$grade" '
        '(expected one of: good, ok, poor).';
  }
  return null;
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

String? _optionValue(List<String> args, String name) {
  final prefix = '$name=';
  for (final a in args) {
    if (a.startsWith(prefix)) return a.substring(prefix.length);
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

String _formatCheck(PerfCheck c) {
  final mark = c.passed ? 'ok  ' : 'FAIL';
  final base = c.baseline.toStringAsFixed(2);
  final cur = c.current.toStringAsFixed(2);
  final lim = c.limit.toStringAsFixed(2);
  return '$mark ${c.name.padRight(24)} '
      'baseline=$base current=$cur limit=$lim';
}
