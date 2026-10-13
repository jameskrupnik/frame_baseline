// Demo app for frame_baseline.
//
// Two deliberately different scrollable screens so the perf harness has
// something real to measure and contrast:
//
//   * "Smooth"  - cheap rows; should stay comfortably inside the frame budget.
//   * "Janky"   - each row burns CPU synchronously during build, so the UI
//                 thread blows past the budget and frames are dropped.
//
// The integration test in `integration_test/perf_test.dart` drives both and
// emits a PerfSummary for each. The contrast is the point: it proves the tool
// reports "good" and "poor" from real engine timings rather than always
// reporting whatever the happy path produces.

import 'dart:math' as math;

import 'package:flutter/material.dart';

part 'home_page.dart';
part 'item_list.dart';
part 'main_row.dart';

void main() => runApp(const DemoApp());

/// Keys the integration test uses to find each list without depending on
/// widget-tree layout.
const smoothListKey = Key('smooth_list');
const jankyListKey = Key('janky_list');
const jankyTabKey = Key('janky_tab');

class DemoApp extends StatelessWidget {
  const DemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'frame_baseline demo',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

/// Deliberately wasteful synchronous computation, sized to push a row's build
/// cost into the milliseconds. Returns a value derived from the work so the
/// compiler cannot optimise the loop away.
double _burnCpu(int seed) {
  var acc = 0.0;
  // Sized so that building a screenful of rows overruns a 60fps frame even on
  // fast desktop hardware; on a phone it is dramatically over budget.
  for (var i = 1; i < 900000; i++) {
    acc += math.sqrt((i * (seed + 1)).toDouble());
  }
  // Normalised to 0..1 purely so the result feeds into a colour.
  return (acc % 1000) / 1000;
}
