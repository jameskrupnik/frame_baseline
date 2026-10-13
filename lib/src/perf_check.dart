part of 'perf_comparator.dart';

/// Outcome of a single metric check within a comparison.
class PerfCheck {
  /// Creates the outcome of checking one metric.
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
