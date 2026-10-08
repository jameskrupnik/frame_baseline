// dart format off
import 'package:frame_baseline/src/frame_stats.dart' show FrameStats;
import 'package:frame_baseline/src/json_fields.dart' show readDouble, readField;
// dart format on

/// Median of [values]; the mean of the middle two when the count is even.
double _median(List<double> values) {
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Whether two frame budgets (ms) are the same, allowing for float noise.
bool sameFrameBudget(double a, double b) => (a - b).abs() <= 1e-9;

/// A jank-focused performance snapshot for a single driven screen scenario.
///
/// `build` covers UI-thread frame build time; `raster` covers GPU-thread raster
/// time. Frames whose build/raster time exceeds [frameBudgetMillis] are "janky".
///
/// Pure Dart so the same model is used on-device (produced from `FrameTiming`s)
/// and on the host (parsed from JSON for comparison against committed goldens).
class PerfSummary {
  /// Creates a summary from already-computed statistics.
  ///
  /// Use [PerfSummary.fromDurations] to compute one from raw frame durations.
  const PerfSummary({
    required this.scenario,
    required this.sampledFrameCount,
    required this.frameBudgetMillis,
    required this.build,
    required this.raster,
    required this.missedBuildBudgetCount,
    required this.missedRasterBudgetCount,
  });

  /// Builds a summary from raw per-frame build/raster durations (ms).
  factory PerfSummary.fromDurations({
    required String scenario,
    required List<double> buildMillis,
    required List<double> rasterMillis,
    required double frameBudgetMillis,
  }) {
    return PerfSummary(
      scenario: scenario,
      sampledFrameCount: buildMillis.length,
      frameBudgetMillis: frameBudgetMillis,
      build: FrameStats.fromMillis(buildMillis),
      raster: FrameStats.fromMillis(rasterMillis),
      missedBuildBudgetCount:
          buildMillis.where((m) => m > frameBudgetMillis).length,
      missedRasterBudgetCount:
          rasterMillis.where((m) => m > frameBudgetMillis).length,
    );
  }

  /// Reduces repeated captures of the *same* scenario to a single summary by
  /// taking the per-metric median across [samples].
  ///
  /// Single-run frame timings are noisy enough that a straight run-vs-baseline
  /// gate false-alarms on unchanged code — back-to-back runs of an identical
  /// build routinely move p90/p99 by 20-30%. Taking the median of a few runs
  /// discards those one-off outliers (a background process, a shader compile)
  /// while preserving a real regression, which shifts every sample.
  ///
  /// Samples that captured no frames are left out when any sample did: with
  /// an even count, an all-zero sample would be averaged into the middle pair
  /// and pull every metric down.
  ///
  /// Throws [ArgumentError] if [samples] is empty, mixes scenarios, or mixes
  /// frame budgets (a 60Hz and a 120Hz capture have no meaningful median).
  factory PerfSummary.medianOf(List<PerfSummary> samples) {
    if (samples.isEmpty) {
      throw ArgumentError.value(samples, 'samples', 'must not be empty');
    }
    final scenario = samples.first.scenario;
    if (samples.any((s) => s.scenario != scenario)) {
      throw ArgumentError.value(
        samples,
        'samples',
        'all samples must be for the same scenario',
      );
    }
    final budget = samples.first.frameBudgetMillis;
    if (samples.any((s) => !sameFrameBudget(s.frameBudgetMillis, budget))) {
      throw ArgumentError.value(
        samples,
        'samples',
        'all samples must share one frame budget, but "$scenario" was '
            'captured at different frame budgets '
            '(${{
          for (final s in samples) s.frameBudgetMillis,
        }.join('ms, ')}ms)',
      );
    }
    final captured = samples.where((s) => s.sampledFrameCount > 0).toList();
    final used = captured.isEmpty ? samples : captured;
    if (used.length == 1) return used.first;

    double med(double Function(PerfSummary) field) =>
        _median(used.map(field).toList());

    return PerfSummary(
      scenario: scenario,
      sampledFrameCount: med((s) => s.sampledFrameCount.toDouble()).round(),
      frameBudgetMillis: med((s) => s.frameBudgetMillis),
      build: FrameStats(
        average: med((s) => s.build.average),
        p50: med((s) => s.build.p50),
        p90: med((s) => s.build.p90),
        p99: med((s) => s.build.p99),
        worst: med((s) => s.build.worst),
      ),
      raster: FrameStats(
        average: med((s) => s.raster.average),
        p50: med((s) => s.raster.p50),
        p90: med((s) => s.raster.p90),
        p99: med((s) => s.raster.p99),
        worst: med((s) => s.raster.worst),
      ),
      missedBuildBudgetCount:
          med((s) => s.missedBuildBudgetCount.toDouble()).round(),
      missedRasterBudgetCount:
          med((s) => s.missedRasterBudgetCount.toDouble()).round(),
    );
  }

  /// Parses a summary from its [toJson] representation.
  ///
  /// Throws a [FormatException] if a field is missing or has the wrong type.
  factory PerfSummary.fromJson(Map<String, dynamic> json) => PerfSummary(
        scenario: readField<String>(json, 'scenario'),
        sampledFrameCount: readField<int>(json, 'sampledFrameCount'),
        frameBudgetMillis: readDouble(json, 'frameBudgetMillis'),
        build: FrameStats.fromJson(
          readField<Map<String, dynamic>>(json, 'build'),
        ),
        raster: FrameStats.fromJson(
          readField<Map<String, dynamic>>(json, 'raster'),
        ),
        missedBuildBudgetCount: readField<int>(json, 'missedBuildBudgetCount'),
        missedRasterBudgetCount:
            readField<int>(json, 'missedRasterBudgetCount'),
      );

  /// Identifier for the driven scenario, e.g. `chat_list_scroll`.
  final String scenario;

  /// Number of frames captured during the driven action.
  final int sampledFrameCount;

  /// Per-frame budget (ms); frames slower than this are counted as janky.
  final double frameBudgetMillis;

  /// UI-thread (build) frame-time statistics.
  final FrameStats build;

  /// GPU-thread (raster) frame-time statistics.
  final FrameStats raster;

  /// Frames whose build time exceeded [frameBudgetMillis].
  final int missedBuildBudgetCount;

  /// Frames whose raster time exceeded [frameBudgetMillis].
  final int missedRasterBudgetCount;

  /// Fraction of sampled frames that missed the budget on the UI thread.
  double get jankyBuildFrameRatio =>
      sampledFrameCount == 0 ? 0 : missedBuildBudgetCount / sampledFrameCount;

  /// Fraction of sampled frames that missed the budget on the GPU thread.
  double get jankyRasterFrameRatio =>
      sampledFrameCount == 0 ? 0 : missedRasterBudgetCount / sampledFrameCount;

  /// Converts this summary to a JSON-encodable map, the inverse of
  /// [PerfSummary.fromJson]. This is the format of a committed baseline file.
  Map<String, dynamic> toJson() => {
        'scenario': scenario,
        'sampledFrameCount': sampledFrameCount,
        'frameBudgetMillis': frameBudgetMillis,
        'build': build.toJson(),
        'raster': raster.toJson(),
        'missedBuildBudgetCount': missedBuildBudgetCount,
        'missedRasterBudgetCount': missedRasterBudgetCount,
      };
}
