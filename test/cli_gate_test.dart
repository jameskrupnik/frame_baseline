// Exercises bin/compare.dart as a subprocess.
//
// The CLI *is* the CI gate, so its exit codes are the contract everything else
// depends on: a gate that exits 0 when it should exit 1 fails silently and
// forever. The library-level tests cannot catch that — only running the binary
// can.
//
// This file: the baseline gate itself, sampling and missing scenarios.

// dart format off
import 'dart:io' show File, ProcessResult;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart' show kPerfSummaryMarker;

import 'support/cli_harness.dart';
// dart format on

void main() {
  final cli = CliHarness();
  ProcessResult run(List<String> lines, {List<String> args = const []}) =>
      cli.run(lines, args: args);

  test('exits 0 when a run matches its baseline', () {
    final lines = [
      logLine(cliSummary(const [4, 5, 6, 7, 8])),
    ];

    expect(run(lines, args: ['--update']).exitCode, 0);
    expect(run(lines).exitCode, 0, reason: 'unchanged run must pass the gate');
  });

  test('exits 1 when a run regresses past tolerance', () {
    run(
      [
        logLine(cliSummary(const [4, 5, 6, 7, 8])),
      ],
      args: [
        '--update',
      ],
    );

    final regressed = run([
      logLine(cliSummary(const [40, 50, 60, 70, 80])),
    ]);
    expect(regressed.exitCode, 1);
    expect(regressed.stdout, contains('FAIL'));
  });

  test('exits 1 when a scenario has no baseline at all', () {
    final result = run([
      logLine(cliSummary(const [4, 5, 6, 7, 8])),
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
        [logLine(cliSummary(const []))],
        args: ['--update'],
      );

      expect(result.exitCode, 1, reason: 'must not exit 0 on a dead capture');
      expect(result.stderr, contains('captured 0 frames'));
      expect(
        File('${cli.tmp.path}/baselines/demo.perf.json').existsSync(),
        isFalse,
        reason: 'an all-zeros golden would pass every future run',
      );
    });

    test('one dead scenario does not stop the others being recorded', () {
      final result = run(
        [
          logLine(cliSummary(const [], scenario: 'dead')),
          logLine(cliSummary(const [4, 5, 6, 7, 8], scenario: 'alive')),
        ],
        args: ['--update'],
      );

      expect(result.exitCode, 1);
      expect(
        File('${cli.tmp.path}/baselines/alive.perf.json').existsSync(),
        isTrue,
      );
      expect(
        File('${cli.tmp.path}/baselines/dead.perf.json').existsSync(),
        isFalse,
      );
    });
  });

  group('median sampling', () {
    test('collapses repeated samples of a scenario', () {
      final result = run(
        [
          logLine(cliSummary(const [4, 4, 4])),
          logLine(cliSummary(const [6, 6, 6])),
          logLine(cliSummary(const [5, 5, 5])),
        ],
        args: ['--update'],
      );

      expect(result.stdout, contains('median of 3 samples'));
      expect(
        File('${cli.tmp.path}/baselines/demo.perf.json').readAsStringSync(),
        contains('"p90": 5.0'),
      );
    });

    test('a single stalled sample does not fail the gate', () {
      run(
        [
          logLine(cliSummary(const [4, 4, 4])),
          logLine(cliSummary(const [4, 4, 4])),
          logLine(cliSummary(const [4, 4, 4])),
        ],
        args: [
          '--update',
        ],
      );

      // Two clean samples and one stall — the median stays clean.
      final result = run([
        logLine(cliSummary(const [4, 4, 4])),
        logLine(cliSummary(const [90, 90, 90])),
        logLine(cliSummary(const [4, 4, 4])),
      ]);

      expect(result.exitCode, 0);
    });

    test('a regression in every sample still fails', () {
      run(
        [
          logLine(cliSummary(const [4, 4, 4])),
        ],
        args: [
          '--update',
        ],
      );

      final result = run([
        logLine(cliSummary(const [40, 40, 40])),
        logLine(cliSummary(const [42, 42, 42])),
        logLine(cliSummary(const [41, 41, 41])),
      ]);

      expect(result.exitCode, 1);
    });
  });

  group('missing scenarios', () {
    final demo = logLine(cliSummary(const [4, 5, 6, 7, 8]));
    final other = logLine(cliSummary(const [4, 5, 6, 7, 8], scenario: 'other'));

    test('fails when a baselined scenario has no line in the log', () {
      run([demo, other], args: ['--update']);

      final result = run([demo]);

      expect(result.exitCode, 1, reason: 'a vanished scenario must not pass');
      expect(result.stderr, contains('Missing scenario "other"'));
    });

    test('fails when a baselined scenario only has a corrupt line', () {
      run([demo, other], args: ['--update']);

      final result = run([
        demo,
        'flutter: $kPerfSummaryMarker{"scenario": "other", "sampled',
      ]);

      expect(result.exitCode, 1);
      expect(result.stderr, contains('unparsable perf line'));
    });

    test('fails on a corrupt line even when every baseline is present', () {
      run([demo], args: ['--update']);

      final result = run([demo, 'flutter: $kPerfSummaryMarker{oops']);

      expect(result.exitCode, 1);
    });

    test('--allow-missing compares only the scenarios that ran', () {
      run([demo, other], args: ['--update']);

      final result = run([demo], args: ['--allow-missing']);

      expect(result.exitCode, 0);
      expect(result.stderr, isNot(contains('Missing scenario')));
    });
  });

  test('an unchanged run is not reported near its limit', () {
    final lines = [
      logLine(
        cliSummary([for (var i = 0; i < 40; i++) i < 30 ? 20 : 4]),
      ),
    ];
    run(lines, args: ['--update']);

    final result = run(lines);
    expect(result.exitCode, 0);
    expect(result.stdout, isNot(contains('near-limit')));
  });

  test('fails with the path, not a stack trace, on a corrupt baseline', () {
    final lines = [
      logLine(cliSummary(const [4, 5, 6, 7, 8])),
    ];
    run(lines, args: ['--update']);
    File('${cli.tmp.path}/baselines/demo.perf.json').writeAsStringSync('{oops');

    final result = run(lines);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Unreadable baseline'));
    expect(result.stderr, contains('demo.perf.json'));
  });
}
