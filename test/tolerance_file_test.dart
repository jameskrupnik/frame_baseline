// The compare CLI reads tolerance bands from a JSON file, so a CI gate can be
// tuned from observed noise (ADOPTION.md, "Tuning") without writing Dart.
// Measured on a simulator, two runs of identical code moved raster.worst from
// 9.9ms to 39ms, which the default +30% band fails.

// dart format off
import 'dart:io' show File, ProcessResult;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart' show PerfTolerance;

import 'support/cli_harness.dart';
// dart format on

void main() {
  group('PerfTolerance.fromJson', () {
    test('uses the defaults for keys it does not set', () {
      final t =
          PerfTolerance.fromJson(const {'maxWorstRasterRegressionRatio': 3});
      expect(t.maxWorstRasterRegressionRatio, 3);
      expect(
        t.maxP90BuildRegressionRatio,
        const PerfTolerance().maxP90BuildRegressionRatio,
      );
      expect(t.jankyFrameSlack, const PerfTolerance().jankyFrameSlack);
    });

    test('rejects an unknown key, so a typo cannot leave a band at its default',
        () {
      expect(
        () => PerfTolerance.fromJson(const {'maxWorstRegressionRatio': 3}),
        throwsFormatException,
      );
    });

    test('rejects a negative or non-numeric band', () {
      expect(
        () => PerfTolerance.fromJson(const {'maxP90BuildRegressionRatio': -1}),
        throwsFormatException,
      );
      expect(
        () => PerfTolerance.fromJson(const {'jankyFrameSlack': 'two'}),
        throwsFormatException,
      );
    });
  });

  group('compare --tolerance', () {
    final cli = CliHarness();
    ProcessResult run(List<String> lines, {List<String> args = const []}) =>
        cli.run(lines, args: args);

    // A hundred steady frames; the run under test stalls one raster frame,
    // which moves only the worst frame.
    final steady = List<double>.filled(100, 4);
    final baseline = logLine(cliSummary([...steady.skip(1), 10]));
    final stalled = logLine(
      cliSummary(steady, raster: [...steady.skip(1), 40]),
    );

    test('a single stalled frame fails the default bands', () {
      run([baseline], args: ['--update']);
      expect(run([stalled]).exitCode, 1);
    });

    test('a wider worst band from the file lets it pass', () {
      run([baseline], args: ['--update']);
      final file = File('${cli.tmp.path}/tolerance.json')
        ..writeAsStringSync('{"maxWorstRasterRegressionRatio": 5}');
      final result = run([stalled], args: ['--tolerance=${file.path}']);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });

    test('a missing tolerance file is a usage error', () {
      run([baseline], args: ['--update']);
      final result = run(
        [stalled],
        args: ['--tolerance=${cli.tmp.path}/nope.json'],
      );
      expect(result.exitCode, 64);
      expect(result.stderr, contains('nope.json'));
    });

    test('an unknown key in the file is a usage error', () {
      run([baseline], args: ['--update']);
      final file = File('${cli.tmp.path}/tolerance.json')
        ..writeAsStringSync('{"maxWorst": 5}');
      final result = run([stalled], args: ['--tolerance=${file.path}']);
      expect(result.exitCode, 64);
      expect(result.stderr, contains('maxWorst'));
    });
  });
}
