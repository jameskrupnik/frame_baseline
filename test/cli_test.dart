// Exercises bin/compare.dart as a subprocess.
//
// The CLI *is* the CI gate, so its exit codes are the contract everything else
// depends on: a gate that exits 0 when it should exit 1 fails silently and
// forever. The library-level tests cannot catch that — only running the binary
// can.

// dart format off
import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File, Process, ProcessResult;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show PerfSummary, kPerfSummaryMarker;
// dart format on

/// Builds a device-log line, including a realistic log prefix to prove the
/// extractor tolerates one.
String _logLine(PerfSummary summary) =>
    'flutter: 00:01 +0: $kPerfSummaryMarker${jsonEncode(summary.toJson())}';

PerfSummary _summary(
  List<double> millis, {
  String scenario = 'demo',
  List<double>? raster,
}) =>
    PerfSummary.fromDurations(
      scenario: scenario,
      buildMillis: millis,
      rasterMillis: raster ?? millis,
      frameBudgetMillis: 16.67,
    );

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('frame_baseline_cli'));
  tearDown(() => tmp.deleteSync(recursive: true));

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

  test('exits 0 when a run matches its baseline', () {
    final lines = [
      _logLine(_summary(const [4, 5, 6, 7, 8]))
    ];

    expect(run(lines, args: ['--update']).exitCode, 0);
    expect(run(lines).exitCode, 0, reason: 'unchanged run must pass the gate');
  });

  test('exits 1 when a run regresses past tolerance', () {
    run([
      _logLine(_summary(const [4, 5, 6, 7, 8]))
    ], args: [
      '--update'
    ]);

    final regressed = run([
      _logLine(_summary(const [40, 50, 60, 70, 80]))
    ]);
    expect(regressed.exitCode, 1);
    expect(regressed.stdout, contains('FAIL'));
  });

  test('exits 1 when a scenario has no baseline at all', () {
    final result = run([
      _logLine(_summary(const [4, 5, 6, 7, 8]))
    ]);
    expect(result.exitCode, 1);
    expect(result.stderr, contains('No baseline'));
  });

  test('exits 1 when the log contains no perf summaries', () {
    final result = run(['flutter: nothing to see here']);
    expect(result.exitCode, 1);
  });

  group('empty captures', () {
    test('refuses to record a zero-frame baseline', () {
      final result = run(
        [_logLine(_summary(const []))],
        args: ['--update'],
      );

      expect(result.exitCode, 1, reason: 'must not exit 0 on a dead capture');
      expect(result.stderr, contains('captured 0 frames'));
      expect(
        File('${tmp.path}/baselines/demo.perf.json').existsSync(),
        isFalse,
        reason: 'an all-zeros golden would pass every future run',
      );
    });

    test('one dead scenario does not stop the others being recorded', () {
      final result = run(
        [
          _logLine(_summary(const [], scenario: 'dead')),
          _logLine(_summary(const [4, 5, 6, 7, 8], scenario: 'alive')),
        ],
        args: ['--update'],
      );

      expect(result.exitCode, 1);
      expect(
        File('${tmp.path}/baselines/alive.perf.json').existsSync(),
        isTrue,
      );
      expect(
          File('${tmp.path}/baselines/dead.perf.json').existsSync(), isFalse);
    });
  });

  group('median sampling', () {
    test('collapses repeated samples of a scenario', () {
      final result = run(
        [
          _logLine(_summary(const [4, 4, 4])),
          _logLine(_summary(const [6, 6, 6])),
          _logLine(_summary(const [5, 5, 5])),
        ],
        args: ['--update'],
      );

      expect(result.stdout, contains('median of 3 samples'));
      expect(
        File('${tmp.path}/baselines/demo.perf.json').readAsStringSync(),
        contains('"p90": 5.0'),
      );
    });

    test('a single stalled sample does not fail the gate', () {
      run([
        _logLine(_summary(const [4, 4, 4])),
        _logLine(_summary(const [4, 4, 4])),
        _logLine(_summary(const [4, 4, 4])),
      ], args: [
        '--update'
      ]);

      // Two clean samples and one stall — the median stays clean.
      final result = run([
        _logLine(_summary(const [4, 4, 4])),
        _logLine(_summary(const [90, 90, 90])),
        _logLine(_summary(const [4, 4, 4])),
      ]);

      expect(result.exitCode, 0);
    });

    test('a regression in every sample still fails', () {
      run([
        _logLine(_summary(const [4, 4, 4]))
      ], args: [
        '--update'
      ]);

      final result = run([
        _logLine(_summary(const [40, 40, 40])),
        _logLine(_summary(const [42, 42, 42])),
        _logLine(_summary(const [41, 41, 41])),
      ]);

      expect(result.exitCode, 1);
    });
  });

  test('writes an HTML report when asked', () {
    final out = '${tmp.path}/report.html';
    run(
      [
        _logLine(_summary(const [4, 5, 6, 7, 8]))
      ],
      args: ['--update', '--report=$out'],
    );

    expect(File(out).readAsStringSync(), contains('<table>'));
  });

  test('exits 64 with no arguments and 66 for a missing log', () {
    expect(
      Process.runSync('dart', ['run', 'bin/compare.dart']).exitCode,
      64,
    );
    expect(
      Process.runSync('dart', ['run', 'bin/compare.dart', 'nope.log']).exitCode,
      66,
    );
  });
}
