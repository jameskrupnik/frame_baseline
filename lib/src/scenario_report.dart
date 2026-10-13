part of 'perf_report.dart';

/// One screen's line in the cross-screen report: its current [summary], the
/// absolute [grade], and — when a baseline existed — the [status] and raw
/// [comparison].
class ScenarioReport {
  /// Creates a report for [summary], deriving [grade] and [status] from it
  /// and from [comparison].
  ScenarioReport({required this.summary, this.comparison, this.drift})
      : grade = gradeSummary(summary),
        status = regressionStatusFor(comparison);

  /// The current run's summary for this screen.
  final PerfSummary summary;

  /// The baseline comparison, or null if there was no baseline.
  final PerfComparison? comparison;

  /// Cumulative drift since the scenario's history began, or null when history
  /// is absent or too short to judge.
  final PerfDrift? drift;

  /// Absolute performance grade (baseline-independent).
  final PerfGrade grade;

  /// Regression verdict relative to the baseline.
  final RegressionStatus status;
}
