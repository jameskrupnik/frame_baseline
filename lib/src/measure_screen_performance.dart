// dart format off
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/foundation.dart'
    show debugPrint, kDebugMode, kProfileMode;
import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// The nominal 60fps frame budget, in milliseconds.
///
/// [measureScreenPerformance] uses it only when the display does not report a
/// refresh rate; otherwise the budget follows the display, so a 120Hz phone is
/// judged against 8.33ms rather than 16.67ms.
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
  /// Creates an exception for [scenario], which captured [sampledFrameCount]
  /// frames against a required [minSampledFrames].
  const InsufficientFrameDataException({
    required this.scenario,
    required this.sampledFrameCount,
    required this.minSampledFrames,
  });

  /// The scenario that was being measured.
  final String scenario;

  /// The number of frames actually captured.
  final int sampledFrameCount;

  /// The number of frames that were required.
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
///
/// [frameBudgetMillis] defaults to one refresh interval of the display the app
/// is drawing on (8.33ms at 120Hz), falling back to
/// [kDefaultFrameBudgetMillis] when the display reports no refresh rate. Pass
/// it to judge every device against the same budget. Throws [ArgumentError]
/// if it is not a positive, finite number.
///
/// Frames the engine finished rasterizing before [action] started are
/// dropped: the engine delivers timings in batches, so the first batch can
/// carry frames from before the measurement began.
Future<PerfSummary> measureScreenPerformance({
  required String scenario,
  required Future<void> Function() action,
  double? frameBudgetMillis,
  int minSampledFrames = kDefaultMinSampledFrames,
  Duration settleDuration = Duration.zero,
}) async {
  if (frameBudgetMillis != null &&
      !(frameBudgetMillis.isFinite && frameBudgetMillis > 0)) {
    throw ArgumentError.value(
      frameBudgetMillis,
      'frameBudgetMillis',
      'must be a positive, finite number of milliseconds',
    );
  }
  final budget = frameBudgetMillis ?? _displayFrameBudgetMillis();

  if (!kProfileMode) {
    debugPrint(
      'frame_baseline: WARNING - measuring "$scenario" in '
      '${kDebugMode ? 'debug' : 'release'} mode. Frame times are only '
      'representative in PROFILE mode on real hardware; do not commit these '
      'numbers as a baseline.',
    );
  }

  // Outside release mode the framework registers a timings callback of its
  // own, so the engine is always collecting and its next batch can hold frames
  // from up to ~100ms before this point. rasterFinishWallTime is stamped from
  // the system clock, so it can be compared with DateTime.
  final startedAt = DateTime.now().microsecondsSinceEpoch;
  final timings = <FrameTiming>[];
  void collector(List<FrameTiming> batch) => timings.addAll(
        batch.where(
          (t) =>
              t.timestampInMicroseconds(FramePhase.rasterFinishWallTime) >=
              startedAt,
        ),
      );

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
    frameBudgetMillis: budget,
  );
}

/// One refresh interval of the display the app draws on, in milliseconds, or
/// [kDefaultFrameBudgetMillis] when the app has no implicit view (a
/// multi-view embedding) or its display reports no rate.
double _displayFrameBudgetMillis() {
  final view = SchedulerBinding.instance.platformDispatcher.implicitView;
  final hz = view?.display.refreshRate ?? 0;
  return hz.isFinite && hz > 0 ? 1000 / hz : kDefaultFrameBudgetMillis;
}
