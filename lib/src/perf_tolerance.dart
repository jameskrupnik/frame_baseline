/// How much regression is allowed before a before/after comparison fails.
///
/// Device-to-device variance means committed goldens are never exact; these
/// tolerances define the band around the baseline that still counts as "no
/// regression". Tune per screen if a scenario is especially noisy.
///
/// Both the UI thread (`build`) and the GPU thread (`raster`) are gated
/// symmetrically, since raster jank is just as user-visible as build jank.
class PerfTolerance {
  const PerfTolerance({
    this.maxP90BuildRegressionRatio = 0.15,
    this.maxP99BuildRegressionRatio = 0.20,
    this.maxWorstBuildRegressionRatio = 0.30,
    this.maxP90RasterRegressionRatio = 0.15,
    this.maxP99RasterRegressionRatio = 0.20,
    this.maxWorstRasterRegressionRatio = 0.30,
    this.maxAdditionalJankyFrameRatio = 0.02,
    this.jankyFrameSlack = 2,
    this.absoluteSlackMillis = 1.0,
  });

  /// Allowed fractional increase in p90 UI-thread build time (0.15 = +15%).
  final double maxP90BuildRegressionRatio;

  /// Allowed fractional increase in p99 UI-thread build time.
  final double maxP99BuildRegressionRatio;

  /// Allowed fractional increase in the worst UI-thread build time.
  final double maxWorstBuildRegressionRatio;

  /// Allowed fractional increase in p90 GPU-thread raster time.
  final double maxP90RasterRegressionRatio;

  /// Allowed fractional increase in p99 GPU-thread raster time.
  final double maxP99RasterRegressionRatio;

  /// Allowed fractional increase in the worst GPU-thread raster time.
  final double maxWorstRasterRegressionRatio;

  /// Extra janky-frame *fraction* tolerated beyond the baseline's rate
  /// (0.02 = +2 percentage points). Applied to both threads. Compared as a
  /// ratio, not a raw count, so runs that happen to capture more or fewer
  /// frames than the baseline are judged fairly. See [jankyFrameSlack] for the
  /// absolute floor.
  final double maxAdditionalJankyFrameRatio;

  /// Absolute floor of extra janky frames always tolerated beyond the
  /// baseline's count, regardless of [maxAdditionalJankyFrameRatio]. Prevents a
  /// baseline with zero (or very few) janky frames from failing on a single
  /// noisy frame.
  final int jankyFrameSlack;

  /// Absolute slack (ms) added to every ratio limit. Prevents tiny baselines
  /// (e.g. 0.4ms) from failing on meaningless sub-millisecond noise.
  final double absoluteSlackMillis;
}
