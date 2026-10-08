// Covers the happy path of measureScreenPerformance.
//
// The widget-test binding never reports real FrameTimings (that is what
// empty_capture_test.dart pins down), so these tests deliver synthetic ones
// through the same platform callback the engine uses. That exercises the
// conversion from engine timings to a summary without needing a device.

// dart format off
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show kDefaultFrameBudgetMillis, measureScreenPerformance;
// dart format on

/// A frame that took [buildMicros] to build and [rasterMicros] to raster.
///
/// It finished rasterizing [age] ago by the wall clock, which is the clock
/// the engine stamps `rasterFinishWallTime` with.
FrameTiming _frame(
  int buildMicros,
  int rasterMicros, {
  Duration age = Duration.zero,
}) {
  const start = 1000;
  final buildFinish = start + buildMicros;
  final rasterFinish = buildFinish + rasterMicros;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: buildFinish,
    rasterStart: buildFinish,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: DateTime.now().subtract(age).microsecondsSinceEpoch,
  );
}

/// Delivers [frames] the way the engine does at the end of a frame batch.
void _report(WidgetTester tester, List<FrameTiming> frames) =>
    tester.binding.platformDispatcher.onReportTimings!(frames);

void main() {
  testWidgets('summarizes the frame timings reported during the action',
      (tester) async {
    final summary = await measureScreenPerformance(
      scenario: 'scroll',
      frameBudgetMillis: 10,
      action: () async => _report(tester, [
        for (var i = 0; i < 5; i++) _frame(4000, 2000),
        _frame(12000, 3000),
      ]),
    );

    expect(summary.scenario, 'scroll');
    expect(summary.sampledFrameCount, 6);
    expect(summary.build.worst, 12);
    expect(summary.raster.p50, 2);
    expect(summary.missedBuildBudgetCount, 1);
    expect(summary.missedRasterBudgetCount, 0);
  });

  testWidgets('keeps collecting through settleDuration', (tester) async {
    // A real delay needs real time, which the widget-test binding only gives
    // inside runAsync.
    final summary = await tester.runAsync(
      () => measureScreenPerformance(
        scenario: 'late_timings',
        settleDuration: const Duration(milliseconds: 20),
        action: () async {
          _report(tester, [for (var i = 0; i < 3; i++) _frame(4000, 2000)]);
          // The engine's final batch arrives after the action returns.
          Future<void>.delayed(
            const Duration(milliseconds: 5),
            () => _report(tester, [
              for (var i = 0; i < 3; i++) _frame(4000, 2000),
            ]),
          ).ignore();
        },
      ),
    );

    // At least the six synthetic frames; the binding may add a real one of its
    // own while real time is running.
    expect(summary!.sampledFrameCount, greaterThanOrEqualTo(6));
  });

  testWidgets('ignores frames rasterized before the action began',
      (tester) async {
    // Outside release mode the framework keeps its own timings callback
    // registered, so the engine collects timings all the time and the first
    // batch after measuring starts carries up to ~100ms of frames from
    // before it — the previous sample's scroll-back, say.
    final summary = await measureScreenPerformance(
      scenario: 'scroll',
      frameBudgetMillis: 10,
      action: () async => _report(tester, [
        _frame(40000, 40000, age: const Duration(seconds: 1)),
        for (var i = 0; i < 5; i++) _frame(4000, 2000),
      ]),
    );

    expect(summary.sampledFrameCount, 5);
    expect(summary.build.worst, 4);
  });

  group('frame budget', () {
    Future<double> budgetFor(WidgetTester tester) async {
      final summary = await measureScreenPerformance(
        scenario: 'scroll',
        action: () async => _report(tester, [
          for (var i = 0; i < 5; i++) _frame(10000, 2000),
        ]),
      );
      return summary.frameBudgetMillis;
    }

    testWidgets('follows a 120 Hz display instead of assuming 60 Hz',
        (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);

      final summary = await measureScreenPerformance(
        scenario: 'scroll',
        action: () async => _report(tester, [
          for (var i = 0; i < 5; i++) _frame(10000, 2000),
        ]),
      );

      expect(summary.frameBudgetMillis, closeTo(1000 / 120, 1e-9));
      // A 10ms build misses a 120 Hz frame, though it would fit at 60 Hz.
      expect(summary.missedBuildBudgetCount, 5);
    });

    testWidgets('falls back to 60 Hz when the display reports no rate',
        (tester) async {
      tester.view.display.refreshRate = 0;
      addTearDown(tester.view.display.resetRefreshRate);

      expect(await budgetFor(tester), kDefaultFrameBudgetMillis);
    });

    testWidgets('an explicit budget wins over the display', (tester) async {
      tester.view.display.refreshRate = 120;
      addTearDown(tester.view.display.resetRefreshRate);

      final summary = await measureScreenPerformance(
        scenario: 'scroll',
        frameBudgetMillis: kDefaultFrameBudgetMillis,
        action: () async => _report(tester, [
          for (var i = 0; i < 5; i++) _frame(10000, 2000),
        ]),
      );

      expect(summary.frameBudgetMillis, kDefaultFrameBudgetMillis);
    });

    testWidgets('rejects a budget that is not a positive, finite number',
        (tester) async {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        await expectLater(
          measureScreenPerformance(
            scenario: 'scroll',
            frameBudgetMillis: bad,
            action: () async {},
          ),
          throwsArgumentError,
          reason: '$bad',
        );
      }
    });
  });
}
