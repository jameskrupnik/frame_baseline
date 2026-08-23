// End-to-end perf capture for the demo app.
//
// This is the on-device half of frame_baseline: it drives each screen inside
// `measureScreenPerformance`, then emits a PERF_SUMMARY_JSON:: line per
// scenario. The host half reads those lines back out of the run log:
//
//   flutter test integration_test/perf_test.dart --profile -d <device> \
//       | tee /tmp/perf.log
//   dart run frame_baseline:compare /tmp/perf.log --baseline-dir=perf/baselines
//
// Must run in PROFILE mode on real hardware. In debug mode the numbers are
// dominated by asserts and JIT; under the plain widget-test binding the engine
// reports no frame timings at all and the capture throws
// InsufficientFrameDataException rather than silently reporting zeros.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart';
import 'package:frame_baseline_example/main.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// How many times each scenario is captured. The host collapses repeated
  /// samples of a scenario to their per-metric median; a single sample is too
  /// noisy to gate on, since back-to-back runs of identical code can move
  /// p90/p99 by 20-30%.
  const sampleCount = 3;

  /// Flings [list] a few times and reports the resulting frame timings, once
  /// per sample.
  Future<void> measureScroll(
    WidgetTester tester, {
    required String scenario,
    required Key list,
  }) async {
    for (var sample = 0; sample < sampleCount; sample++) {
      final summary = await measureScreenPerformance(
        scenario: scenario,
        action: () async {
          for (var i = 0; i < 5; i++) {
            await tester.fling(find.byKey(list), const Offset(0, -500), 4000);
            await tester.pumpAndSettle();
          }
        },
        // Give the engine time to deliver its final batch of FrameTimings
        // before the callback is detached; they arrive asynchronously after
        // raster.
        settleDuration: const Duration(milliseconds: 500),
      );

      reportPerfSummary(summary);

      // Scroll back to the top so every sample measures the same work.
      await tester.fling(find.byKey(list), const Offset(0, 20000), 20000);
      await tester.pumpAndSettle();
    }
  }

  testWidgets('smooth list scroll performance', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    await measureScroll(
      tester,
      scenario: 'smooth_list_scroll',
      list: smoothListKey,
    );
  });

  testWidgets('janky list scroll performance', (tester) async {
    await tester.pumpWidget(const DemoApp());
    await tester.pumpAndSettle();

    // Switch to the expensive tab before measuring.
    await tester.tap(find.byKey(jankyTabKey));
    await tester.pumpAndSettle();

    await measureScroll(
      tester,
      scenario: 'janky_list_scroll',
      list: jankyListKey,
    );
  });
}
