// A capture records the build mode it was measured in, so a debug capture
// cannot quietly become a committed baseline. Debug frame times are
// dominated by asserts and JIT and say nothing about release performance.

// dart format off
import 'dart:io' show File, ProcessResult;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart' show PerfSummary;

import 'support/cli_harness.dart';
// dart format on

PerfSummary _summary(String? buildMode) => PerfSummary.fromDurations(
      scenario: 'demo',
      buildMillis: const [4, 5, 6, 7, 8],
      rasterMillis: const [4, 5, 6, 7, 8],
      frameBudgetMillis: 16.67,
      buildMode: buildMode,
    );

void main() {
  group('PerfSummary.buildMode', () {
    test('round-trips through JSON', () {
      final json = _summary('profile').toJson();
      expect(json['buildMode'], 'profile');
      expect(PerfSummary.fromJson(json).buildMode, 'profile');
    });

    test('is null for summaries written before it existed', () {
      final json = _summary('profile').toJson()..remove('buildMode');
      expect(PerfSummary.fromJson(json).buildMode, isNull);
    });

    test('is left out of the JSON when unknown', () {
      expect(_summary(null).toJson().containsKey('buildMode'), isFalse);
    });

    test('rejects a value that is not a build mode', () {
      final json = _summary('profile').toJson()..['buildMode'] = 'fast';
      expect(() => PerfSummary.fromJson(json), throwsFormatException);
    });
  });

  group('compare', () {
    final cli = CliHarness();
    ProcessResult run(List<String> lines, {List<String> args = const []}) =>
        cli.run(lines, args: args);

    test('--update refuses a debug capture', () {
      final result = run([logLine(_summary('debug'))], args: ['--update']);
      expect(result.exitCode, 1);
      expect(result.stderr, contains('debug'));
      expect(
        File('${cli.tmp.path}/baselines/demo.perf.json').existsSync(),
        isFalse,
        reason: 'a refused capture must not be written',
      );
    });

    test('--update writes a debug capture with --allow-debug-baseline', () {
      final result = run(
        [logLine(_summary('debug'))],
        args: ['--update', '--allow-debug-baseline'],
      );
      expect(result.exitCode, 0);
    });

    test('--update writes a profile capture', () {
      expect(
        run([logLine(_summary('profile'))], args: ['--update']).exitCode,
        0,
      );
    });

    test('warns when comparing a debug capture', () {
      run([logLine(_summary('profile'))], args: ['--update']);
      final result = run([logLine(_summary('debug'))]);
      expect(result.stdout, contains('debug'));
    });
  });
}
