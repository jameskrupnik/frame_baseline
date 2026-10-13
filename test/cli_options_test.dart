// CLI tests for its options: the grade gate, the HTML report, argument
// validation and the scenarios it refuses. See cli_gate_test.dart for why the
// CLI is tested as a subprocess.

// dart format off
import 'dart:io' show File, Process, ProcessResult;

import 'package:flutter_test/flutter_test.dart';

import 'support/cli_harness.dart';
// dart format on

void main() {
  final cli = CliHarness();
  ProcessResult run(List<String> lines, {List<String> args = const []}) =>
      cli.run(lines, args: args);

  group('absolute grade gate', () {
    // A 16.67ms budget: 20ms frames are over it on any device, so this gate
    // needs no baseline and survives being run on different hardware.
    const janky = [20.0, 20.0, 20.0];
    const fast = [2.0, 2.0, 2.0];

    test('fails a screen that is over budget, with no baseline involved', () {
      final result = run(
        [logLine(cliSummary(janky))],
        args: ['--update', '--fail-on-grade=poor'],
      );

      expect(result.exitCode, 1);
      expect(result.stderr, contains('grades poor'));
    });

    test('passes a fast screen', () {
      final result = run(
        [logLine(cliSummary(fast))],
        args: ['--update', '--fail-on-grade=poor'],
      );

      expect(result.exitCode, 0);
    });

    test('catches a screen whose baseline was recorded already slow', () {
      // The blind spot this closes: baseline the screen while it is janky and
      // every later run compares clean forever.
      run([logLine(cliSummary(janky))], args: ['--update']);

      final baselineGate = run([logLine(cliSummary(janky))]);
      expect(
        baselineGate.exitCode,
        0,
        reason: 'the baseline comparison is satisfied by a slow screen',
      );

      final gradeGate = run(
        [logLine(cliSummary(janky))],
        args: ['--fail-on-grade=poor'],
      );
      expect(
        gradeGate.exitCode,
        1,
        reason: 'the absolute gate still catches it',
      );
    });

    test('a stricter threshold also rejects merely ok screens', () {
      // ~9ms of a 16.67ms budget: over half, so "ok" rather than "good".
      final result = run(
        [
          logLine(cliSummary(const [9.0, 9.0, 9.0])),
        ],
        args: ['--update', '--fail-on-grade=ok'],
      );

      expect(result.exitCode, 1);
    });

    test('rejects an unknown threshold name', () {
      final result = run(
        [logLine(cliSummary(fast))],
        args: ['--fail-on-grade=blazing'],
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Unknown --fail-on-grade'));
    });
  });

  test('writes an HTML report when asked', () {
    final out = '${cli.tmp.path}/report.html';
    run(
      [
        logLine(cliSummary(const [4, 5, 6, 7, 8])),
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

  group('argument validation', () {
    // Each of these used to be ignored, which silently switched a gate off
    // while the build stayed green.
    final lines = [
      logLine(cliSummary(const [4, 5, 6, 7, 8])),
    ];

    test('rejects an unknown or misspelt option', () {
      final result = run(lines, args: ['--updtae']);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('Unknown option "--updtae"'));
    });

    test('rejects a value written after a space instead of =', () {
      final result = run(lines, args: ['--fail-on-grade', 'poor']);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--fail-on-grade needs a value'));
    });

    test('rejects a value on an on/off flag', () {
      final result = run(lines, args: ['--update=true']);

      expect(result.exitCode, 64);
      expect(result.stderr, contains('--update does not take a value'));
    });

    test('--help prints usage and exits 0', () {
      final result = Process.runSync('dart', [
        'run',
        'bin/compare.dart',
        '--help',
      ]);

      expect(result.exitCode, 0);
      expect(result.stdout, contains('Usage:'));
    });
  });

  test('refuses a scenario name that would escape the baseline directory', () {
    final result = run(
      [
        logLine(cliSummary(const [4, 5, 6, 7, 8], scenario: '../escaped')),
      ],
      args: ['--update'],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('Refusing scenario "../escaped"'));
    expect(File('${cli.tmp.path}/escaped.perf.json').existsSync(), isFalse);
  });

  test('refuses scenario names that share a baseline file on macOS/Windows',
      () {
    // Case-insensitive file systems map both names to one file, so one
    // scenario's baseline would silently overwrite the other's.
    final result = run(
      [
        logLine(cliSummary(const [4, 5, 6, 7, 8], scenario: 'Home')),
        logLine(cliSummary(const [9, 9, 9, 9, 9], scenario: 'home')),
      ],
      args: ['--update'],
    );

    expect(result.exitCode, 1);
    expect(result.stderr, contains('"Home"'));
    expect(result.stderr, contains('"home"'));
  });

  test('fails a scenario whose samples were captured at different budgets', () {
    // A log from a 60 Hz and a 120 Hz device has no meaningful median.
    final lines = [
      logLine(cliSummary(const [4, 5, 6, 7, 8])),
      logLine(cliSummary(const [4, 5, 6, 7, 8], budget: 1000 / 120)),
      logLine(cliSummary(const [4, 5, 6, 7, 8], scenario: 'other')),
    ];

    final result = run(lines, args: ['--update']);

    expect(result.exitCode, 1);
    expect(result.stderr, contains('different frame budgets'));
    expect(
      File('${cli.tmp.path}/baselines/demo.perf.json').existsSync(),
      isFalse,
    );
    expect(
      File('${cli.tmp.path}/baselines/other.perf.json').existsSync(),
      isTrue,
      reason: 'one bad scenario must not stop the others',
    );
  });
}
