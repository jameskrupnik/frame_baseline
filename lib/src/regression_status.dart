part of 'perf_report.dart';

/// A regression verdict for a screen relative to its committed baseline.
///
/// Answers "did this change make it worse?"; see [PerfGrade] for the absolute
/// question.
enum RegressionStatus {
  /// Comfortably within tolerance.
  pass,

  /// Passing, but some metric has used 90% or more of the headroom its
  /// tolerance allows above the baseline.
  nearLimit,

  /// At least one metric regressed past tolerance.
  regressed,

  /// No baseline to compare against (e.g. first run / `--update`).
  noBaseline,
}

/// A passing metric that has used this fraction of its headroom — the gap
/// between its baseline and its limit — is flagged
/// [RegressionStatus.nearLimit] rather than [RegressionStatus.pass].
const double kNearLimitFraction = 0.9;

/// Derives a [RegressionStatus] from a comparison, or [RegressionStatus.noBaseline]
/// when [comparison] is null.
RegressionStatus regressionStatusFor(PerfComparison? comparison) {
  if (comparison == null) return RegressionStatus.noBaseline;
  if (!comparison.passed) return RegressionStatus.regressed;
  return comparison.checks.any(_isNearLimit)
      ? RegressionStatus.nearLimit
      : RegressionStatus.pass;
}

/// Whether [check] has used [kNearLimitFraction] of the headroom between its
/// baseline and its limit.
///
/// Measured from the baseline, not from zero: a limit is the baseline plus a
/// tolerance, so with a tolerance under ~11% an unchanged metric already sits
/// past 90% of its limit. A metric no worse than its baseline is never near,
/// which also covers a zero-headroom limit.
bool _isNearLimit(PerfCheck check) {
  if (check.current <= check.baseline) return false;
  final headroom = check.limit - check.baseline;
  return check.current >= check.baseline + headroom * kNearLimitFraction;
}
