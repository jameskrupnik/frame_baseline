// Exercises bin/compare.dart as a subprocess.
//
// The CLI *is* the CI gate, so its exit codes are the contract everything else
// depends on: a gate that exits 0 when it should exit 1 fails silently and
// forever. The library-level tests cannot catch that — only running the binary
// can.

// dart format off
import 'dart:convert' show jsonEncode;
import 'dart:io' show Directory, File, FileMode, Process, ProcessResult;

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

  group('history and drift', () {
    /// Records [millis] as one run in the history file, via the CLI.
    void record(String history, double millis, {String? label}) {
      run(
        [
          _logLine(_summary([millis, millis, millis])),
        ],
        args: [
          '--update',
          '--history=$history',
          if (label != null) '--label=$label',
        ],
      );
    }

    test('appends a line per run and records the label', () {
      final history = '${tmp.path}/history.jsonl';
      record(history, 4, label: 'abc123');
      record(history, 5, label: 'def456');

      final lines = File(history).readAsLinesSync()
        ..removeWhere((l) => l.trim().isEmpty);
      expect(lines, hasLength(2));
      expect(lines.first, contains('abc123'));
      expect(lines.last, contains('def456'));
    });

    test('reports cumulative drift once there is enough history', () {
      final history = '${tmp.path}/history.jsonl';
      for (var i = 0; i < 3; i++) {
        record(history, 4);
      }

      // A run far slower than the recorded origin.
      final result = run(
        [
          _logLine(_summary(const [12, 12, 12])),
        ],
        args: ['--history=$history'],
      );

      expect(result.stdout, contains('drift='));
      expect(result.stdout, contains('DRIFT since history began'));
    });

    test('does not fail the gate on drift unless asked', () {
      final history = '${tmp.path}/history.jsonl';
      for (var i = 0; i < 3; i++) {
        record(history, 4);
      }
      // Re-baseline so the per-change gate itself is clean.
      run([
        _logLine(_summary(const [12, 12, 12])),
      ], args: [
        '--update',
        '--history=$history',
      ]);

      final lenient = run(
        [
          _logLine(_summary(const [12, 12, 12])),
        ],
        args: ['--history=$history'],
      );
      expect(lenient.exitCode, 0, reason: 'drift is advisory by default');

      final strict = run(
        [
          _logLine(_summary(const [12, 12, 12])),
        ],
        args: ['--history=$history', '--fail-on-drift'],
      );
      expect(strict.exitCode, 1, reason: '--fail-on-drift must gate on drift');
    });

    test('catches creep that every individual comparison let through', () {
      final history = '${tmp.path}/history.jsonl';

      // Each step is a ~12% regression, inside the per-change tolerance, and
      // re-baselines as it goes — exactly how creep ships unnoticed.
      const steps = <double>[4.0, 4.5, 5.0, 5.6, 6.3, 7.1, 7.9];
      for (final step in steps) {
        final result = run(
          [
            _logLine(_summary([step, step, step])),
          ],
          args: ['--history=$history'],
        );
        // Not the first few runs, which have no baseline yet.
        if (step != steps.first) {
          expect(result.stdout, isNot(contains('FAIL')),
              reason: 'step $step must pass the per-change gate');
        }
        run([
          _logLine(_summary([step, step, step])),
        ], args: [
          '--update',
          '--baseline-dir=${tmp.path}/baselines',
        ]);
      }

      final finalRun = run(
        [
          _logLine(_summary(const [7.9, 7.9, 7.9])),
        ],
        args: ['--history=$history', '--fail-on-drift'],
      );

      expect(finalRun.exitCode, 1,
          reason: 'the accumulated doubling must be caught');
      expect(finalRun.stdout, contains('DRIFT since history began'));
    });

    test('does not record a run whose capture was empty', () {
      final history = '${tmp.path}/history.jsonl';
      run(
        [_logLine(_summary(const []))],
        args: ['--update', '--history=$history'],
      );

      expect(File(history).existsSync(), isFalse,
          reason: 'a dead run would poison the trend');
    });

    test('survives a corrupt history line', () {
      final history = '${tmp.path}/history.jsonl';
      record(history, 4);
      File(history).writeAsStringSync('{ not json\n', mode: FileMode.append);

      final result = run(
        [
          _logLine(_summary(const [4, 4, 4])),
        ],
        args: ['--history=$history'],
      );

      expect(result.stderr, contains('unparsable history line'));
      expect(result.exitCode, 0);
    });

    test('rejects --fail-on-drift without a history file', () {
      final result = run(
        [
          _logLine(_summary(const [4, 4, 4])),
        ],
        args: ['--fail-on-drift'],
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('requires --history'));
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
