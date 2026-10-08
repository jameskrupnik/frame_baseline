// dart format off
import 'dart:math' as math show max;

import 'package:frame_baseline/src/json_fields.dart' show readDouble;
// dart format on

/// Summary statistics for a series of per-frame durations, in milliseconds.
///
/// Pure Dart (no Flutter/`dart:ui` imports) so it can be reused by the host
/// comparator CLI as well as on-device measurement.
class FrameStats {
  /// Creates stats from already-computed values, in milliseconds.
  ///
  /// Use [FrameStats.fromMillis] to compute them from raw frame durations.
  const FrameStats({
    required this.average,
    required this.p50,
    required this.p90,
    required this.p99,
    required this.worst,
  });

  /// Computes stats from a list of per-frame durations in milliseconds.
  factory FrameStats.fromMillis(List<double> millis) {
    if (millis.isEmpty) {
      return const FrameStats(average: 0, p50: 0, p90: 0, p99: 0, worst: 0);
    }
    final sorted = [...millis]..sort();
    final sum = sorted.fold<double>(0, (a, b) => a + b);
    return FrameStats(
      average: sum / sorted.length,
      p50: _percentile(sorted, 50),
      p90: _percentile(sorted, 90),
      p99: _percentile(sorted, 99),
      worst: math.max(sorted.last, 0),
    );
  }

  /// Parses stats from its [toJson] representation.
  ///
  /// Throws a [FormatException] if a field is missing or not a number.
  factory FrameStats.fromJson(Map<String, dynamic> json) => FrameStats(
        average: readDouble(json, 'average'),
        p50: readDouble(json, 'p50'),
        p90: readDouble(json, 'p90'),
        p99: readDouble(json, 'p99'),
        worst: readDouble(json, 'worst'),
      );

  /// Mean frame duration (ms).
  final double average;

  /// Median (50th percentile) frame duration (ms).
  final double p50;

  /// 90th percentile frame duration (ms).
  final double p90;

  /// 99th percentile frame duration (ms).
  final double p99;

  /// Slowest single frame (ms).
  final double worst;

  /// Converts these stats to a JSON-encodable map, the inverse of
  /// [FrameStats.fromJson].
  Map<String, dynamic> toJson() => {
        'average': average,
        'p50': p50,
        'p90': p90,
        'p99': p99,
        'worst': worst,
      };
}

/// Linear-interpolated percentile of an already-sorted, non-empty list.
double _percentile(List<double> sorted, double p) {
  if (sorted.isEmpty) return 0;
  if (sorted.length == 1) return sorted.first;
  final rank = (p / 100) * (sorted.length - 1);
  final low = rank.floor();
  final high = rank.ceil();
  if (low == high) return sorted[low];
  final weight = rank - low;
  return sorted[low] * (1 - weight) + sorted[high] * weight;
}
