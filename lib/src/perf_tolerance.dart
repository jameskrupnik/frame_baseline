/// How much regression is allowed before a before/after comparison fails.
///
/// Device-to-device variance means committed goldens are never exact; these
/// tolerances define the band around the baseline that still counts as "no
/// regression". Tune per screen if a scenario is especially noisy.
class PerfTolerance {
  const PerfTolerance({
    this.maxP90BuildRegressionRatio = 0.15,
    this.maxP99BuildRegressionRatio = 0.20,
    this.maxWorstBuildRegressionRatio = 0.30,
    this.maxAdditionalMissedBuildBudgetFrames = 2,
    this.absoluteSlackMillis = 1.0,
  });

  /// Allowed fractional increase in p90 UI-thread build time (0.15 = +15%).
  final double maxP90BuildRegressionRatio;

  /// Allowed fractional increase in p99 UI-thread build time.
  final double maxP99BuildRegressionRatio;

  /// Allowed fractional increase in the worst UI-thread build time.
  final double maxWorstBuildRegressionRatio;

  /// Extra janky frames tolerated beyond the baseline's count.
  final int maxAdditionalMissedBuildBudgetFrames;

  /// Absolute slack (ms) added to every ratio limit. Prevents tiny baselines
  /// (e.g. 0.4ms) from failing on meaningless sub-millisecond noise.
  final double absoluteSlackMillis;
}
