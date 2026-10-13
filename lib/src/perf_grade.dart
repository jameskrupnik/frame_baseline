part of 'perf_report.dart';

/// An absolute performance grade for a single screen, judged against its
/// frame budget.
///
/// Independent of any baseline, it answers "is this screen fast?".
///
/// Declared from healthiest to worst, so [severity] (and [index]) order them.
enum PerfGrade {
  /// Comfortably smooth: p90 well under budget and almost no janky frames.
  good,

  /// Acceptable but watch it: approaching budget or some janky frames.
  ok,

  /// Janky: a p90 over budget or a meaningful share of missed frames.
  poor,

  /// No frames were captured, so the screen's performance is simply unknown.
  ///
  /// Distinct from [good]: an empty capture has zero for every metric, and
  /// grading that as flawless is how a broken measurement masquerades as a
  /// healthy one.
  unknown;

  /// Parses a grade threshold name (`good`, `ok`, `poor`), ignoring case and
  /// surrounding whitespace, or returns null if [name] isn't one.
  ///
  /// [unknown] is deliberately not parseable: it describes a failed
  /// measurement, not a threshold anyone would gate on.
  static PerfGrade? tryParse(String name) =>
      switch (name.trim().toLowerCase()) {
        'good' => good,
        'ok' => ok,
        'poor' => poor,
        _ => null,
      };

  /// Rank from healthiest (0) to worst, so callers can express thresholds
  /// like "fail if anything is [poor] or worse".
  ///
  /// [unknown] ranks worst: a screen we failed to measure is never evidence
  /// that the screen is fine.
  int get severity => index;
}

/// A screen's absolute grade is `good` while its worst-thread p90 stays under
/// this fraction of the frame budget (and jank stays under [kGoodJankRatio]).
const double kGoodP90BudgetFraction = 0.5;

/// Above [kGoodP90BudgetFraction] but at/under this fraction of budget grades
/// `ok`; a p90 over this is `poor`.
const double kOkP90BudgetFraction = 1;

/// Max janky-frame fraction still allowed for a `good` grade (1%).
const double kGoodJankRatio = 0.01;

/// Max janky-frame fraction still allowed for an `ok` grade (5%).
const double kOkJankRatio = 0.05;

/// Grades [summary] on absolute performance against its own frame budget.
///
/// Uses the worse of the build and raster threads for both the p90 and the
/// janky-frame fraction, so a screen is only as good as its slowest thread.
PerfGrade gradeSummary(PerfSummary summary) {
  if (summary.sampledFrameCount <= 0) return PerfGrade.unknown;
  final budget = summary.frameBudgetMillis;
  final p90 = math.max(summary.build.p90, summary.raster.p90);
  final jank = math.max(
    summary.jankyBuildFrameRatio,
    summary.jankyRasterFrameRatio,
  );
  final p90Fraction = budget <= 0 ? double.infinity : p90 / budget;

  if (p90Fraction <= kGoodP90BudgetFraction && jank <= kGoodJankRatio) {
    return PerfGrade.good;
  }
  if (p90Fraction <= kOkP90BudgetFraction && jank <= kOkJankRatio) {
    return PerfGrade.ok;
  }
  return PerfGrade.poor;
}

/// Absolute threshold bucket for a single frame-time metric (ms), used to color
/// individual cells. Mirrors [gradeSummary]'s per-metric logic.
PerfGrade gradeMillis(double millis, double budget) {
  final fraction = budget <= 0 ? double.infinity : millis / budget;
  if (fraction <= kGoodP90BudgetFraction) return PerfGrade.good;
  if (fraction <= kOkP90BudgetFraction) return PerfGrade.ok;
  return PerfGrade.poor;
}

/// Absolute threshold bucket for a janky-frame fraction (0..1).
PerfGrade gradeJankRatio(double ratio) {
  if (ratio <= kGoodJankRatio) return PerfGrade.good;
  if (ratio <= kOkJankRatio) return PerfGrade.ok;
  return PerfGrade.poor;
}
