/// How much regression is allowed before a before/after comparison fails.
///
/// Device-to-device variance means committed goldens are never exact; these
/// tolerances define the band around the baseline that still counts as "no
/// regression". Tune per screen if a scenario is especially noisy.
///
/// Both the UI thread (`build`) and the GPU thread (`raster`) are gated
/// symmetrically, since raster jank is just as user-visible as build jank.
class PerfTolerance {
  /// Creates a tolerance band; the defaults are the per-change gate.
  ///
  /// See [PerfTolerance.drift] for the looser band used for cumulative drift.
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

  /// Reads a tolerance from [json], such as a `--tolerance` file. Keys are the
  /// field names below; any key it leaves out keeps its default.
  ///
  /// Throws a [FormatException] for an unknown key or a value that is not a
  /// non-negative number (a whole number for `jankyFrameSlack`), so a typo
  /// cannot silently leave a band at its default.
  factory PerfTolerance.fromJson(Map<String, dynamic> json) {
    const known = {
      'maxP90BuildRegressionRatio',
      'maxP99BuildRegressionRatio',
      'maxWorstBuildRegressionRatio',
      'maxP90RasterRegressionRatio',
      'maxP99RasterRegressionRatio',
      'maxWorstRasterRegressionRatio',
      'maxAdditionalJankyFrameRatio',
      'jankyFrameSlack',
      'absoluteSlackMillis',
    };
    final unknown = json.keys.where((k) => !known.contains(k)).toList();
    if (unknown.isNotEmpty) {
      throw FormatException(
        'unknown tolerance key ${unknown.map((k) => '"$k"').join(', ')} '
        '(expected any of: ${known.join(', ')})',
      );
    }
    const d = PerfTolerance();
    double ratio(String key, double fallback) {
      final value = json[key];
      if (value == null) return fallback;
      if (value is num && value.isFinite && value >= 0) return value.toDouble();
      throw FormatException(
        'expected "$key" to be a non-negative number, got $value',
      );
    }

    final slack = json['jankyFrameSlack'];
    if (slack != null && (slack is! int || slack < 0)) {
      throw FormatException(
        'expected "jankyFrameSlack" to be a non-negative whole number, '
        'got $slack',
      );
    }
    return PerfTolerance(
      maxP90BuildRegressionRatio:
          ratio('maxP90BuildRegressionRatio', d.maxP90BuildRegressionRatio),
      maxP99BuildRegressionRatio:
          ratio('maxP99BuildRegressionRatio', d.maxP99BuildRegressionRatio),
      maxWorstBuildRegressionRatio:
          ratio('maxWorstBuildRegressionRatio', d.maxWorstBuildRegressionRatio),
      maxP90RasterRegressionRatio:
          ratio('maxP90RasterRegressionRatio', d.maxP90RasterRegressionRatio),
      maxP99RasterRegressionRatio:
          ratio('maxP99RasterRegressionRatio', d.maxP99RasterRegressionRatio),
      maxWorstRasterRegressionRatio: ratio(
        'maxWorstRasterRegressionRatio',
        d.maxWorstRasterRegressionRatio,
      ),
      maxAdditionalJankyFrameRatio: ratio(
        'maxAdditionalJankyFrameRatio',
        d.maxAdditionalJankyFrameRatio,
      ),
      jankyFrameSlack: (slack as int?) ?? d.jankyFrameSlack,
      absoluteSlackMillis: ratio('absoluteSlackMillis', d.absoluteSlackMillis),
    );
  }

  /// Tolerance for *cumulative* drift since a scenario's history began, as used
  /// by `analyzeDrift`.
  ///
  /// Looser than the per-change gate by design: it spans many accepted changes,
  /// each of which was individually allowed to add up to 15%. The point is not
  /// to re-litigate any single change but to catch the total — a screen that
  /// has quietly become half again as slow as it started.
  static const PerfTolerance drift = PerfTolerance(
    maxP90BuildRegressionRatio: 0.50,
    maxP99BuildRegressionRatio: 0.60,
    maxWorstBuildRegressionRatio: 0.75,
    maxP90RasterRegressionRatio: 0.50,
    maxP99RasterRegressionRatio: 0.60,
    maxWorstRasterRegressionRatio: 0.75,
    maxAdditionalJankyFrameRatio: 0.05,
    jankyFrameSlack: 3,
  );

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

  /// The extra janky-frame *fraction* tolerated beyond the baseline's rate.
  ///
  /// 0.02 means +2 percentage points. Applied to both threads. Compared as a
  /// ratio, not a raw count, so runs that happen to capture more or fewer
  /// frames than the baseline are judged fairly. See [jankyFrameSlack] for the
  /// absolute floor.
  final double maxAdditionalJankyFrameRatio;

  /// The number of extra janky frames always tolerated beyond the baseline's
  /// count, regardless of [maxAdditionalJankyFrameRatio].
  ///
  /// Prevents a
  /// baseline with zero (or very few) janky frames from failing on a single
  /// noisy frame.
  final int jankyFrameSlack;

  /// The absolute slack, in milliseconds, added to every ratio limit.
  ///
  /// Prevents tiny baselines
  /// (e.g. 0.4ms) from failing on meaningless sub-millisecond noise.
  final double absoluteSlackMillis;
}
