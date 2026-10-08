// dart format off
import 'package:frame_baseline/src/perf_comparator.dart'
    show PerfComparator, PerfComparison;
import 'package:frame_baseline/src/perf_history.dart' show PerfHistoryEntry;
import 'package:frame_baseline/src/perf_summary.dart'
    show PerfSummary, sameFrameBudget;
import 'package:frame_baseline/src/perf_tolerance.dart' show PerfTolerance;
// dart format on

/// How many of the oldest history entries form the reference point that current
/// runs are measured against.
///
/// More than one so the anchor is a median rather than whichever single run
/// happened to be recorded first.
const int kDefaultReferenceWindow = 3;

/// Cumulative drift of a scenario since its history began.
///
/// This is a different question from the baseline gate. The gate asks "did
/// *this* change make it worse?" and is deliberately blind to history — so a
/// sequence of individually-innocent changes each land well inside tolerance
/// while the screen ends up far slower than where it started. Drift asks "are
/// we slower than we used to be?", which no single comparison can answer.
class PerfDrift {
  /// Creates a drift result. Usually obtained from [analyzeDrift] instead.
  const PerfDrift({
    required this.scenario,
    required this.reference,
    required this.current,
    required this.comparison,
    required this.referenceSampleCount,
    required this.totalSampleCount,
  });

  /// Scenario analysed.
  final String scenario;

  /// Median of the oldest [referenceSampleCount] runs — the anchor.
  final PerfSummary reference;

  /// The run being judged.
  final PerfSummary current;

  /// Reference-vs-current verdict, using the drift tolerance.
  final PerfComparison comparison;

  /// How many historical runs were medianed into [reference].
  final int referenceSampleCount;

  /// Total runs recorded for this scenario at [current]'s frame budget.
  final int totalSampleCount;

  /// Whether cumulative drift exceeded the drift tolerance.
  bool get drifted => !comparison.passed;

  /// The fractional change in build p90 since the reference.
  ///
  /// 0.35 means 35% slower; negative means the screen got faster. Infinite
  /// when the reference was zero and the current run is not.
  double get buildP90DriftRatio =>
      _ratio(reference.build.p90, current.build.p90);

  /// The fractional change in raster p90 since the reference.
  ///
  /// Same scale as [buildP90DriftRatio].
  double get rasterP90DriftRatio =>
      _ratio(reference.raster.p90, current.raster.p90);

  /// The larger of the build and raster p90 drifts — the headline number.
  double get worstP90DriftRatio => buildP90DriftRatio >= rasterP90DriftRatio
      ? buildP90DriftRatio
      : rasterP90DriftRatio;

  static double _ratio(double from, double to) {
    if (from <= 0) return to <= 0 ? 0 : double.infinity;
    return (to - from) / from;
  }
}

/// Measures how far [current] has drifted from the start of [history].
///
/// [history] must contain only entries for the scenario being analysed, oldest
/// first. Entries recorded at a different frame budget from [current] (another
/// device's refresh rate) are left out, since their jank counts measure
/// something else. Returns null when fewer than [referenceWindow] runs remain —
/// too little signal to call anything a trend.
///
/// The anchor is the *oldest* window rather than a rolling one on purpose:
/// anchoring to recent runs would let creep hide, since each new run quietly
/// becomes the new normal. When a slowdown is deliberate and accepted, reset
/// the anchor by truncating the history file — the same intentional act as
/// re-recording a baseline.
PerfDrift? analyzeDrift({
  required List<PerfHistoryEntry> history,
  required PerfSummary current,
  int referenceWindow = kDefaultReferenceWindow,
  PerfTolerance tolerance = PerfTolerance.drift,
}) {
  final comparable = [
    for (final e in history)
      if (sameFrameBudget(
        e.summary.frameBudgetMillis,
        current.frameBudgetMillis,
      ))
        e,
  ];
  if (comparable.length < referenceWindow) return null;

  final window = comparable.take(referenceWindow).toList(growable: false);
  final reference = PerfSummary.medianOf(
    window.map((e) => e.summary).toList(growable: false),
  );

  return PerfDrift(
    scenario: current.scenario,
    reference: reference,
    current: current,
    comparison: PerfComparator(tolerance: tolerance)
        .compare(baseline: reference, current: current),
    referenceSampleCount: window.length,
    totalSampleCount: comparable.length,
  );
}
