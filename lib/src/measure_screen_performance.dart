// dart format off
import 'dart:ui' show FrameTiming;

import 'package:flutter/scheduler.dart' show SchedulerBinding;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// Nominal 60fps frame budget in milliseconds. Override for 90/120Hz devices.
const double kDefaultFrameBudgetMillis = 1000 / 60;

/// Drives [action] while recording engine frame timings, then returns a
/// jank-focused [PerfSummary].
///
/// IMPORTANT: run in **profile** mode on a **real device**. Debug-mode and
/// simulator/emulator numbers are dominated by asserts/JIT and are not
/// representative of shipped performance.
///
/// Uses `SchedulerBinding.addTimingsCallback`, so it captures real engine
/// FrameTimings (build + raster) without needing VM-service timeline extraction.
Future<PerfSummary> measureScreenPerformance({
  required String scenario,
  required Future<void> Function() action,
  double frameBudgetMillis = kDefaultFrameBudgetMillis,
}) async {
  final timings = <FrameTiming>[];
  void collector(List<FrameTiming> batch) => timings.addAll(batch);

  SchedulerBinding.instance.addTimingsCallback(collector);
  try {
    await action();
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collector);
  }

  double toMillis(Duration d) => d.inMicroseconds / 1000;

  return PerfSummary.fromDurations(
    scenario: scenario,
    buildMillis: [for (final t in timings) toMillis(t.buildDuration)],
    rasterMillis: [for (final t in timings) toMillis(t.rasterDuration)],
    frameBudgetMillis: frameBudgetMillis,
  );
}
