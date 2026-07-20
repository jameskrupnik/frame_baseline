// dart format off
import 'dart:math' as math show max;

import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
import 'package:frame_baseline/src/perf_tolerance.dart' show PerfTolerance;
// dart format on

/// Outcome of a single metric check within a comparison.
class PerfCheck {
  const PerfCheck({
    required this.name,
    required this.baseline,
    required this.current,
    required this.limit,
    required this.passed,
  });

  /// Metric name, e.g. `build.p90`.
  final String name;

  /// Baseline value for this metric.
  final double baseline;

  /// Current-run value for this metric.
  final double current;

  /// The largest [current] value that still passes.
  final double limit;

  /// Whether [current] is within [limit].
  final bool passed;
}

/// Result of comparing a current [PerfSummary] against a baseline golden.
class PerfComparison {
  const PerfComparison({required this.scenario, required this.checks});

  /// Scenario the comparison was run for.
  final String scenario;

  /// Per-metric check outcomes.
  final List<PerfCheck> checks;

  /// True when every check passed.
  bool get passed => checks.every((c) => c.passed);

  /// The checks that failed.
  List<PerfCheck> get regressions =>
      checks.where((c) => !c.passed).toList(growable: false);
}

/// Compares a current performance snapshot against a committed baseline,
/// applying [PerfTolerance] so device variance doesn't cause false failures.
class PerfComparator {
  const PerfComparator({this.tolerance = const PerfTolerance()});

  /// Tolerance band applied to each metric.
  final PerfTolerance tolerance;

  /// Compares [current] against [baseline], returning a per-metric verdict.
  PerfComparison compare({
    required PerfSummary baseline,
    required PerfSummary current,
  }) {
    final checks = <PerfCheck>[
      _ratioCheck(
        'build.p90',
        baseline.build.p90,
        current.build.p90,
        tolerance.maxP90BuildRegressionRatio,
      ),
      _ratioCheck(
        'build.p99',
        baseline.build.p99,
        current.build.p99,
        tolerance.maxP99BuildRegressionRatio,
      ),
      _ratioCheck(
        'build.worst',
        baseline.build.worst,
        current.build.worst,
        tolerance.maxWorstBuildRegressionRatio,
      ),
      _jankCheck('missedBuildBudgetCount', baseline, current,
          (s) => s.missedBuildBudgetCount),
      _ratioCheck(
        'raster.p90',
        baseline.raster.p90,
        current.raster.p90,
        tolerance.maxP90RasterRegressionRatio,
      ),
      _ratioCheck(
        'raster.p99',
        baseline.raster.p99,
        current.raster.p99,
        tolerance.maxP99RasterRegressionRatio,
      ),
      _ratioCheck(
        'raster.worst',
        baseline.raster.worst,
        current.raster.worst,
        tolerance.maxWorstRasterRegressionRatio,
      ),
      _jankCheck('missedRasterBudgetCount', baseline, current,
          (s) => s.missedRasterBudgetCount),
    ];
    return PerfComparison(scenario: current.scenario, checks: checks);
  }

  PerfCheck _ratioCheck(
    String name,
    double baseline,
    double current,
    double maxRatio,
  ) {
    // Allow the greater of a proportional bump or a small absolute bump, so
    // both large and near-zero baselines get a sane tolerance band.
    final limit = math.max(
      baseline * (1 + maxRatio),
      baseline + tolerance.absoluteSlackMillis,
    );
    return PerfCheck(
      name: name,
      baseline: baseline,
      current: current,
      limit: limit,
      passed: current <= limit,
    );
  }

  /// Gates a janky-frame count. The limit is derived from the baseline's janky
  /// *rate* scaled to the current run's frame count — so runs of different
  /// lengths compare fairly — with an absolute floor of [PerfTolerance.jankyFrameSlack]
  /// extra frames so tiny/zero-jank baselines aren't hair-trigger. Displayed in
  /// frame-count units for readability.
  PerfCheck _jankCheck(
    String name,
    PerfSummary baseline,
    PerfSummary current,
    int Function(PerfSummary) missedBudgetCount,
  ) {
    final baselineCount = missedBudgetCount(baseline);
    final currentCount = missedBudgetCount(current);
    final baselineRatio = baseline.sampledFrameCount == 0
        ? 0.0
        : baselineCount / baseline.sampledFrameCount;
    final allowedRatio = baselineRatio + tolerance.maxAdditionalJankyFrameRatio;
    final limit = math.max(
      allowedRatio * current.sampledFrameCount,
      baselineCount + tolerance.jankyFrameSlack.toDouble(),
    );
    return PerfCheck(
      name: name,
      baseline: baselineCount.toDouble(),
      current: currentCount.toDouble(),
      limit: limit,
      passed: currentCount <= limit,
    );
  }
}
