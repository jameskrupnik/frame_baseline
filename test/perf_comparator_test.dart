// dart format off
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show PerfComparator, PerfSummary, PerfTolerance;
// dart format on

PerfSummary _summary({
  required List<double> buildMillis,
  String scenario = 'demo',
  List<double>? rasterMillis,
}) {
  return PerfSummary.fromDurations(
    scenario: scenario,
    buildMillis: buildMillis,
    rasterMillis: rasterMillis ?? buildMillis,
    frameBudgetMillis: 16.67,
  );
}

void main() {
  group('PerfSummary', () {
    test('computes jank counts and percentiles from durations', () {
      final s = _summary(buildMillis: [2, 4, 6, 8, 20, 30]);
      expect(s.sampledFrameCount, 6);
      expect(s.missedBuildBudgetCount, 2); // 20 and 30 exceed 16.67
      expect(s.build.worst, 30);
      expect(s.jankyBuildFrameRatio, closeTo(2 / 6, 1e-9));
      expect(s.jankyRasterFrameRatio, closeTo(2 / 6, 1e-9));
    });

    test('round-trips through JSON', () {
      final s = _summary(buildMillis: [1, 2, 3, 40]);
      final restored = PerfSummary.fromJson(s.toJson());
      expect(restored.toJson(), s.toJson());
    });
  });

  group('PerfComparator', () {
    const comparator = PerfComparator();

    test('passes when current matches baseline', () {
      final baseline = _summary(buildMillis: [4, 5, 6, 7, 8]);
      final current = _summary(buildMillis: [4, 5, 6, 7, 8]);
      final result = comparator.compare(baseline: baseline, current: current);
      expect(result.passed, isTrue);
      expect(result.regressions, isEmpty);
    });

    test('fails when p90 build time regresses beyond tolerance', () {
      final baseline = _summary(buildMillis: [4, 4, 4, 4, 8]);
      final current = _summary(buildMillis: [4, 4, 4, 4, 40]);
      final result = comparator.compare(baseline: baseline, current: current);
      expect(result.passed, isFalse);
      expect(result.regressions.map((c) => c.name), contains('build.worst'));
    });

    test('fails when additional frames miss the budget', () {
      final baseline = _summary(buildMillis: [4, 4, 4, 4, 4]);
      final current = _summary(buildMillis: [40, 40, 40, 40, 40]);
      final result = comparator.compare(baseline: baseline, current: current);
      expect(result.passed, isFalse);
      expect(
        result.regressions.map((c) => c.name),
        contains('missedBuildBudgetCount'),
      );
    });

    test('catches a raster-only regression that leaves build clean', () {
      // Build times are identical; only raster regresses.
      final baseline = _summary(
        buildMillis: [4, 4, 4, 4, 4],
        rasterMillis: [4, 4, 4, 4, 8],
      );
      final current = _summary(
        buildMillis: [4, 4, 4, 4, 4],
        rasterMillis: [4, 4, 4, 4, 40],
      );
      final result = comparator.compare(baseline: baseline, current: current);
      expect(result.passed, isFalse);
      final regressed = result.regressions.map((c) => c.name);
      expect(regressed, contains('raster.worst'));
      expect(regressed, isNot(contains('build.worst')));
    });

    test('janky-frame gate scales with frame count, not raw difference', () {
      // Baseline: 1 janky frame in 10 (10%). Current: 2 janky in 20 (10%) —
      // same rate, double the raw count. A raw +count gate would flag this;
      // the ratio-based gate must not.
      final baseline = _summary(
        buildMillis: [4, 4, 4, 4, 4, 4, 4, 4, 4, 40],
      );
      final current = _summary(
        buildMillis: [
          4, 4, 4, 4, 4, 4, 4, 4, 4, 40, //
          4, 4, 4, 4, 4, 4, 4, 4, 4, 40
        ],
      );
      final jank = comparator
          .compare(baseline: baseline, current: current)
          .checks
          .firstWhere((c) => c.name == 'missedBuildBudgetCount');
      expect(jank.current, 2);
      expect(jank.passed, isTrue);
    });

    test('absolute slack ignores sub-millisecond noise on tiny baselines', () {
      // Baseline p90 ~0.5ms; current ~1.2ms is a huge ratio but tiny absolute.
      final baseline = _summary(buildMillis: [0.4, 0.5, 0.5, 0.5, 0.6]);
      final current = _summary(buildMillis: [0.9, 1.0, 1.1, 1.1, 1.2]);
      final result = comparator.compare(baseline: baseline, current: current);
      expect(
        result.checks.firstWhere((c) => c.name == 'build.p90').passed,
        isTrue,
      );
    });

    test('respects a stricter custom tolerance', () {
      const strict = PerfComparator(
        tolerance: PerfTolerance(
          maxP90BuildRegressionRatio: 0.01,
          absoluteSlackMillis: 0.01,
        ),
      );
      final baseline = _summary(buildMillis: [10, 10, 10, 10, 10]);
      final current = _summary(buildMillis: [12, 12, 12, 12, 12]);
      final result = strict.compare(baseline: baseline, current: current);
      expect(result.passed, isFalse);
    });
  });
}
