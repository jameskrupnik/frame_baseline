// Shared set-up for the CLI tests, which run bin/compare.dart as a
// subprocess.

// dart format off
import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File, Process, ProcessResult;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show PerfSummary, kPerfSummaryMarker;
// dart format on

/// Builds a device-log line, including a realistic log prefix to prove the
/// extractor tolerates one.
String logLine(PerfSummary summary) =>
    'flutter: 00:01 +0: $kPerfSummaryMarker${jsonEncode(summary.toJson())}';

/// A summary for [scenario] with [millis] as its build times and, unless
/// [raster] is given, its raster times.
PerfSummary cliSummary(
  List<double> millis, {
  String scenario = 'demo',
  List<double>? raster,
  double budget = 16.67,
}) =>
    PerfSummary.fromDurations(
      scenario: scenario,
      buildMillis: millis,
      rasterMillis: raster ?? millis,
      frameBudgetMillis: budget,
    );

/// A fresh temporary directory per test, and the CLI run against it.
///
/// Create one at the top of `main`: it registers its own `setUp` and
/// `tearDown`.
class CliHarness {
  /// Registers the per-test temporary directory.
  CliHarness() {
    setUp(() => _tmp = Directory.systemTemp.createTempSync('frame_baseline'));
    tearDown(() => _tmp.deleteSync(recursive: true));
  }

  late Directory _tmp;

  /// This test's temporary directory; baselines go in `baselines/` under it.
  Directory get tmp => _tmp;

  /// Runs the CLI over a log containing [lines].
  ProcessResult run(List<String> lines, {List<String> args = const []}) {
    final log = File('${tmp.path}/device.log')
      ..writeAsStringSync(lines.join('\n'));
    return Process.runSync('dart', [
      'run',
      'bin/compare.dart',
      log.path,
      '--baseline-dir=${tmp.path}/baselines',
      ...args,
    ]);
  }
}
