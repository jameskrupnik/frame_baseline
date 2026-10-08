// Tests for median-of-N sampling, the mitigation for run-to-run noise.
//
// Measured on real hardware, back-to-back runs of an *identical* build moved
// build.p90 by ~27% and build.p99 by ~24% — past the default tolerance bands,
// so a single-sample gate reported a regression on unchanged code. Taking the
// median across samples is what makes the gate trustworthy.

// dart format off
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show PerfComparator, PerfSummary;
// dart format on

PerfSummary _summary(
  List<double> millis, {
  String scenario = 'demo',
  double budget = 16.67,
}) =>
    PerfSummary.fromDurations(
      scenario: scenario,
      buildMillis: millis,
      rasterMillis: millis,
      frameBudgetMillis: budget,
    );

void main() {
  group('PerfSummary.medianOf', () {
    test('returns the sample itself when there is only one', () {
      final only = _summary(const [4, 5, 6]);
      expect(PerfSummary.medianOf([only]), same(only));
    });

    test('takes the per-metric median across samples', () {
      final median = PerfSummary.medianOf([
        _summary(const [10, 10, 10]),
        _summary(const [2, 2, 2]),
        _summary(const [6, 6, 6]),
      ]);

      expect(median.build.p90, 6);
      expect(median.raster.p90, 6);
    });

    test('averages the middle two for an even sample count', () {
      final median = PerfSummary.medianOf([
        _summary(const [2, 2, 2]),
        _summary(const [4, 4, 4]),
        _summary(const [6, 6, 6]),
        _summary(const [8, 8, 8]),
      ]);

      expect(median.build.p90, 5);
    });

    test('discards a single outlier run rather than being dragged by it', () {
      // Two clean runs and one that hit a stall. The mean would be pulled
      // upward; the median should not be.
      final median = PerfSummary.medianOf([
        _summary(const [4, 4, 4]),
        _summary(const [400, 400, 400]),
        _summary(const [5, 5, 5]),
      ]);

      expect(median.build.worst, 5);
    });

    test('an outlier sample no longer trips the gate', () {
      final baseline = _summary(const [4, 4, 4]);
      final noisy = _summary(const [40, 40, 40]);
      final clean = _summary(const [4, 4, 4]);

      // The noisy sample alone is a hard failure...
      expect(
        const PerfComparator()
            .compare(baseline: baseline, current: noisy)
            .passed,
        isFalse,
      );

      // ...but as one of three samples it is outvoted.
      final median = PerfSummary.medianOf([clean, noisy, clean]);
      expect(
        const PerfComparator()
            .compare(baseline: baseline, current: median)
            .passed,
        isTrue,
      );
    });

    test('a genuine regression present in every sample still fails', () {
      final baseline = _summary(const [4, 4, 4]);
      final regressed = _summary(const [40, 40, 40]);

      // Median-of-N must not mask a real regression: it moves every sample.
      final median = PerfSummary.medianOf([regressed, regressed, regressed]);
      expect(
        const PerfComparator()
            .compare(baseline: baseline, current: median)
            .passed,
        isFalse,
      );
    });

    test('medians the janky-frame counts too', () {
      final median = PerfSummary.medianOf([
        _summary(const [20, 20, 1]), // 2 janky
        _summary(const [20, 1, 1]), // 1 janky
        _summary(const [20, 20, 20]), // 3 janky
      ]);

      expect(median.missedBuildBudgetCount, 2);
    });

    test('rejects an empty sample list', () {
      expect(() => PerfSummary.medianOf([]), throwsArgumentError);
    });

    test('rejects samples from different scenarios', () {
      expect(
        () => PerfSummary.medianOf([
          _summary(const [4], scenario: 'a'),
          _summary(const [4], scenario: 'b'),
        ]),
        throwsArgumentError,
      );
    });

    test('rejects samples captured at different frame budgets', () {
      // Two 60 Hz and 120 Hz samples would median to a 12.5ms budget nobody
      // ran at, and their missed-frame counts measure different things.
      expect(
        () => PerfSummary.medianOf([
          _summary(const [4, 5, 6]),
          _summary(const [4, 5, 6], budget: 1000 / 120),
        ]),
        throwsArgumentError,
      );
    });

    test('ignores an empty capture when real ones exist', () {
      // With an even count, an all-zero sample would be averaged into the
      // middle pair and halve every metric — hiding a regression.
      final median = PerfSummary.medianOf([
        _summary(const []),
        _summary(const [10, 10, 10]),
      ]);

      expect(median.sampledFrameCount, 3);
      expect(median.build.p90, 10);
    });

    test('an all-empty sample set stays empty', () {
      final median = PerfSummary.medianOf([
        _summary(const []),
        _summary(const []),
      ]);

      expect(median.sampledFrameCount, 0);
    });
  });
}
