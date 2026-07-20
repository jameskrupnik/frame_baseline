// dart format off
import 'package:frame_baseline/src/frame_stats.dart' show FrameStats;
// dart format on

/// A jank-focused performance snapshot for a single driven screen scenario.
///
/// `build` covers UI-thread frame build time; `raster` covers GPU-thread raster
/// time. Frames whose build/raster time exceeds [frameBudgetMillis] are "janky".
///
/// Pure Dart so the same model is used on-device (produced from `FrameTiming`s)
/// and on the host (parsed from JSON for comparison against committed goldens).
class PerfSummary {
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

  /// Parses a summary from its [toJson] representation.
  factory PerfSummary.fromJson(Map<String, dynamic> json) => PerfSummary(
        scenario: json['scenario'] as String,
        sampledFrameCount: json['sampledFrameCount'] as int,
        frameBudgetMillis: (json['frameBudgetMillis'] as num).toDouble(),
        build: FrameStats.fromJson(json['build'] as Map<String, dynamic>),
        raster: FrameStats.fromJson(json['raster'] as Map<String, dynamic>),
        missedBuildBudgetCount: json['missedBuildBudgetCount'] as int,
        missedRasterBudgetCount: json['missedRasterBudgetCount'] as int,
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
