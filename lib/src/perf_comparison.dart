part of 'perf_comparator.dart';

/// Result of comparing a current [PerfSummary] against a baseline golden.
class PerfComparison {
  /// Creates a comparison result for [scenario].
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

  /// Fatal reasons the comparison could not be trusted at all.
  ///
  /// Currently an empty capture on either side. Unlike [warnings] these fail
  /// the gate, since
  /// a zero-frame summary passes every metric check vacuously and would
  /// otherwise report a regression-free green.
  final List<String> errors;

  /// Whether there were no fatal [errors] and every check passed.
  bool get passed => errors.isEmpty && checks.every((c) => c.passed);

  /// The checks that failed.
  List<PerfCheck> get regressions =>
      checks.where((c) => !c.passed).toList(growable: false);
}
