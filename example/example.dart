// A runnable illustration of the frame_baseline comparison API.
//
// In a real app you would call `measureScreenPerformance` + `reportPerfSummary`
// inside an integration test (see the "Integration test usage" section below),
// run it in profile mode on a device, then feed the log to
// `dart run frame_baseline:compare`. That flow needs a device, so this example
// exercises only the pure comparison layer, which runs anywhere.

// ignore_for_file: avoid_print

// Imports the pure comparison layer directly so this example runs under the
// plain Dart VM (`dart run example/example.dart`). Application code should use
// the public barrel instead: `import 'package:frame_baseline/frame_baseline.dart';`
import 'package:frame_baseline/src/perf_comparator.dart' show PerfComparator;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;

void main() {
  final baseline = PerfSummary.fromDurations(
    scenario: 'home_scroll',
    buildMillis: const [4, 5, 6, 7, 8],
    rasterMillis: const [5, 6, 7, 8, 9],
    frameBudgetMillis: 16.67,
  );

  final current = PerfSummary.fromDurations(
    scenario: 'home_scroll',
    buildMillis: const [4, 5, 6, 30, 40], // regressed: two janky frames
    rasterMillis: const [5, 6, 7, 8, 9],
    frameBudgetMillis: 16.67,
  );

  final result = const PerfComparator().compare(
    baseline: baseline,
    current: current,
  );

  print('scenario: ${result.scenario}  passed: ${result.passed}');
  for (final check in result.checks) {
    print(
      '  ${check.passed ? "ok  " : "FAIL"} ${check.name}: '
      'baseline=${check.baseline} current=${check.current} '
      'limit=${check.limit.toStringAsFixed(2)}',
    );
  }
}

// ---------------------------------------------------------------------------
// Integration test usage (pseudo-code — needs the `integration_test` package
// and a real profile-mode device):
//
//   import 'package:frame_baseline/frame_baseline.dart';
//
//   testWidgets('home scroll performance', (tester) async {
//     await tester.pumpWidget(const MyApp());
//     // ...navigate to the screen...
//
//     final summary = await measureScreenPerformance(
//       scenario: 'home_scroll',
//       action: () async {
//         await tester.fling(find.byType(Scrollable).first, Offset(0, -400), 3000);
//         await tester.pumpAndSettle();
//       },
//     );
//     reportPerfSummary(summary); // prints PERF_SUMMARY_JSON:: ... to the log
//   });
//
// Then on the host:
//   dart run frame_baseline:compare device.log --baseline-dir=perf/baselines
// ---------------------------------------------------------------------------
