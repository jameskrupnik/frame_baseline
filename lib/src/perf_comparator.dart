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

/// A current run whose sampled frame count diverges from the baseline's by more
/// than this factor (in either direction) is flagged: the scenario likely
/// changed or the capture was truncated, making percentiles unreliable.
const double kFrameCountDivergenceFactor = 2;

/// Result of comparing a current [PerfSummary] against a baseline golden.
class PerfComparison {
  const PerfComparison({
    required this.scenario,
    required this.checks,
    this.warnings = const [],
    this.errors = const [],
  });

  /// Scenario the comparison was run for.
  final String scenario;

  /// Per-metric check outcomes.
  final List<PerfCheck> checks;

  /// Non-fatal notes about the comparison's *validity* (distinct from
  /// regressions), e.g. the baseline and current run used different frame
  /// budgets, or their frame counts diverge enough that the scenario may have
  /// changed. Empty when the two captures look comparable.
  final List<String> warnings;

  /// Fatal reasons the comparison could not be trusted at all — currently an
  /// empty capture on either side. Unlike [warnings] these fail the gate, since
  /// a zero-frame summary passes every metric check vacuously and would
  /// otherwise report a regression-free green.
  final List<String> errors;

  /// True when there were no fatal [errors] and every check passed.
  bool get passed => errors.isEmpty && checks.every((c) => c.passed);

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
  ///
  /// If either side captured no frames the comparison short-circuits to a
  /// failure: every metric of an empty summary is zero, so it would otherwise
  /// pass all eight checks and report a clean bill of health for a measurement
  /// that never happened.
  PerfComparison compare({
    required PerfSummary baseline,
    required PerfSummary current,
  }) {
    final errors = _emptyCaptureErrors(baseline, current);
    if (errors.isNotEmpty) {
      return PerfComparison(
        scenario: current.scenario,
        checks: const [],
        errors: errors,
      );
    }

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
      _jankCheck(
        'missedBuildBudgetCount',
        baseline,
        current,
        (s) => s.missedBuildBudgetCount,
      ),
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
      _jankCheck(
        'missedRasterBudgetCount',
        baseline,
        current,
        (s) => s.missedRasterBudgetCount,
      ),
    ];
    return PerfComparison(
      scenario: current.scenario,
      checks: checks,
      warnings: _warnings(baseline, current),
    );
  }

  /// Fatal validity problems: a capture with no frames in it. Kept separate
  /// from [_warnings] because these make the verdict meaningless rather than
  /// merely suspect.
  List<String> _emptyCaptureErrors(PerfSummary baseline, PerfSummary current) {
    final errors = <String>[];
    if (baseline.sampledFrameCount <= 0) {
      errors.add(
        'baseline captured 0 frames, so it encodes no performance information. '
        'Delete it and re-record with --update from a real profile-mode run.',
      );
    }
    if (current.sampledFrameCount <= 0) {
      errors.add(
        'current run captured 0 frames, so there is nothing to compare. The '
        'measurement likely never ran (widget test instead of integration '
        'test, or an action that drove no frames).',
      );
    }
    return errors;
  }

  /// Flags captures that aren't meaningfully comparable, without failing the
  /// gate — the numbers are still reported, but callers are told to distrust
  /// them.
  List<String> _warnings(PerfSummary baseline, PerfSummary current) {
    final warnings = <String>[];
    if ((baseline.frameBudgetMillis - current.frameBudgetMillis).abs() > 1e-9) {
      warnings.add(
        'frame budget differs (baseline ${baseline.frameBudgetMillis}ms vs '
        'current ${current.frameBudgetMillis}ms); jank-count checks are not '
        'directly comparable.',
      );
    }
    final b = baseline.sampledFrameCount;
    final c = current.sampledFrameCount;
    if (b > 0 &&
        c > 0 &&
        (c > b * kFrameCountDivergenceFactor ||
            b > c * kFrameCountDivergenceFactor)) {
      warnings.add(
        'sampled frame count diverges (baseline $b vs current $c); the scenario '
        'may have changed or the capture was truncated.',
      );
    }
    return warnings;
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
