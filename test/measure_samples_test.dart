// measureScreenPerformanceSamples captures a scenario several times, reports
// each sample and resets the screen between them: the loop every suite
// otherwise writes around measureScreenPerformance (see ADOPTION.md).

// dart format off
import 'dart:async' show ZoneSpecification, runZoned;
import 'dart:ui' show FrameTiming;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show
        InsufficientFrameDataException,
        kPerfSummaryMarker,
        measureScreenPerformanceSamples;
// dart format on

FrameTiming _frame() {
  const start = 1000;
  return FrameTiming(
    vsyncStart: start,
    buildStart: start,
    buildFinish: start + 4000,
    rasterStart: start + 4000,
    rasterFinish: start + 6000,
    rasterFinishWallTime: DateTime.now().microsecondsSinceEpoch,
  );
}

void _report(WidgetTester tester, int frames) =>
    tester.binding.platformDispatcher.onReportTimings!([
      for (var i = 0; i < frames; i++) _frame(),
    ]);

void main() {
  testWidgets('captures, reports and resets each sample', (tester) async {
    final printed = <String>[];
    var resets = 0;
    final summaries = await runZoned(
      () => measureScreenPerformanceSamples(
        scenario: 'scroll',
        frameBudgetMillis: 16,
        action: () async => _report(tester, 6),
        reset: () async => resets++,
      ),
      zoneSpecification: ZoneSpecification(
        print: (_, __, ___, line) => printed.add(line),
      ),
    );

    expect(summaries, hasLength(3));
    expect(summaries.map((s) => s.scenario), everyElement('scroll'));
    expect(
      printed.where((l) => l.contains(kPerfSummaryMarker)),
      hasLength(3),
      reason: 'every sample is reported for the host to take the median',
    );
    expect(resets, 2, reason: 'reset runs between samples, not after the last');
  });

  testWidgets('takes the sample count it is given', (tester) async {
    final summaries = await runZoned(
      () => measureScreenPerformanceSamples(
        scenario: 'scroll',
        samples: 5,
        frameBudgetMillis: 16,
        action: () async => _report(tester, 6),
      ),
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
    );
    expect(summaries, hasLength(5));
  });

  testWidgets('rejects fewer than one sample', (tester) async {
    await expectLater(
      measureScreenPerformanceSamples(
        scenario: 'scroll',
        samples: 0,
        action: () async {},
      ),
      throwsArgumentError,
    );
  });

  testWidgets('still fails loudly on a capture with too few frames',
      (tester) async {
    await expectLater(
      runZoned(
        () => measureScreenPerformanceSamples(
          scenario: 'scroll',
          frameBudgetMillis: 16,
          action: () async => _report(tester, 1),
        ),
        zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
      ),
      throwsA(isA<InsufficientFrameDataException>()),
    );
  });
}
