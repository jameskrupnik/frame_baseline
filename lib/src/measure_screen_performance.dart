// dart format off
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kProfileMode;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// Nominal 60fps frame budget in milliseconds. Override for 90/120Hz devices.
const double kDefaultFrameBudgetMillis = 1000 / 60;

/// Fewest frames a capture may contain and still be treated as meaningful.
///
/// Percentiles over a handful of frames are noise, and a capture of *zero*
/// frames means the measurement never happened at all — see
/// [InsufficientFrameDataException].
const int kDefaultMinSampledFrames = 5;

/// Thrown when [measureScreenPerformance] captured too few frames to produce a
/// trustworthy [PerfSummary].
///
/// This is deliberately fatal rather than a silent empty summary: a zero-frame
/// capture grades as flawless and passes every comparison check, so swallowing
/// it would turn a broken setup into a permanently green perf gate.
class InsufficientFrameDataException implements Exception {
  const InsufficientFrameDataException({
    required this.scenario,
    required this.sampledFrameCount,
    required this.minSampledFrames,
  });

  /// Scenario that was being measured.
  final String scenario;

  /// How many frames were actually captured.
  final int sampledFrameCount;

  /// How many were required.
  final int minSampledFrames;

  @override
  String toString() =>
      'InsufficientFrameDataException: scenario "$scenario" captured '
      '$sampledFrameCount frame(s), which is below the required '
      '$minSampledFrames.\n'
      'The engine only reports FrameTimings for frames it actually rasterizes, '
      'so this usually means one of:\n'
      '  1. This is a widget test (`flutter test`). Frame timings are never '
      'reported under the widget-test binding — perf measurement must run as an '
      '`integration_test` on a device.\n'
      '  2. The `action` callback did not drive any frames (no animation, or it '
      'returned before pumping).\n'
      '  3. The capture was cut short before the engine reported its timings; '
      'try passing a non-zero `settleDuration`.\n'
      'If a genuinely short capture is expected, lower `minSampledFrames`.';
}

/// Drives [action] while recording engine frame timings, then returns a
/// jank-focused [PerfSummary].
///
/// IMPORTANT: run in **profile** mode on a **real device**. Debug-mode and
/// simulator/emulator numbers are dominated by asserts/JIT and are not
/// representative of shipped performance; a warning is logged if the build mode
/// is anything other than profile.
///
/// Uses `SchedulerBinding.addTimingsCallback`, so it captures real engine
/// FrameTimings (build + raster) without needing VM-service timeline extraction.
///
/// Throws [InsufficientFrameDataException] if fewer than [minSampledFrames]
/// frames were captured, so a broken measurement fails loudly instead of
/// producing an all-zeros summary that would silently pass every gate.
///
/// [settleDuration], when non-zero, waits after [action] completes before
/// detaching the callback, giving the engine time to deliver its final batch of
/// timings. Only use it where real time advances (an `integration_test`); under
/// the widget-test binding a delay stalls until the fake clock is pumped.
Future<PerfSummary> measureScreenPerformance({
  required String scenario,
  required Future<void> Function() action,
  double frameBudgetMillis = kDefaultFrameBudgetMillis,
  int minSampledFrames = kDefaultMinSampledFrames,
  Duration settleDuration = Duration.zero,
}) async {
  if (!kProfileMode) {
    debugPrint(
      'frame_baseline: WARNING - measuring "$scenario" in '
      '${kDebugMode ? 'debug' : 'release'} mode. Frame times are only '
      'representative in PROFILE mode on real hardware; do not commit these '
      'numbers as a baseline.',
    );
  }

  final timings = <FrameTiming>[];
  void collector(List<FrameTiming> batch) => timings.addAll(batch);

  SchedulerBinding.instance.addTimingsCallback(collector);
  try {
    await action();
    if (settleDuration > Duration.zero) {
      await Future<void>.delayed(settleDuration);
    }
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collector);
  }

  if (timings.length < minSampledFrames) {
    throw InsufficientFrameDataException(
      scenario: scenario,
      sampledFrameCount: timings.length,
      minSampledFrames: minSampledFrames,
    );
  }

  double toMillis(Duration d) => d.inMicroseconds / 1000;

  return PerfSummary.fromDurations(
    scenario: scenario,
    buildMillis: [for (final t in timings) toMillis(t.buildDuration)],
    rasterMillis: [for (final t in timings) toMillis(t.rasterDuration)],
    frameBudgetMillis: frameBudgetMillis,
  );
}
