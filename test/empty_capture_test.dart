// Regression tests for the "silent green" failure mode: a capture that
// recorded no frames has zero for every metric, which trivially satisfies every
// tolerance band. Left unguarded, a measurement that never ran reports a
// perfectly healthy screen forever. Each layer must refuse it independently.

// dart format off
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show
        InsufficientFrameDataException,
        PerfComparator,
        PerfGrade,
        PerfSummary,
        gradeSummary,
        measureScreenPerformance;
// dart format on

PerfSummary _summary(List<double> millis, {String scenario = 'demo'}) =>
    PerfSummary.fromDurations(
      scenario: scenario,
      buildMillis: millis,
      rasterMillis: millis,
      frameBudgetMillis: 16.67,
    );

void main() {
  group('measureScreenPerformance', () {
    testWidgets(
        'throws rather than returning an all-zeros summary when the '
        'binding reports no frames', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('hi')));

      // The widget-test binding never delivers engine FrameTimings, so this is
      // exactly the setup mistake the exception exists to catch. Caught by hand
      // rather than with expectLater/throwsA: those are themselves guarded test
      // APIs, and wrapping a call that pumps inside one trips the framework's
      // guarded-function conflict check before the throw is ever observed.
      Object? caught;
      try {
        await measureScreenPerformance(
          scenario: 'never_measured',
          action: () async {
            await tester.pump();
          },
        );
      } catch (e) {
        caught = e;
      }

      expect(
        caught,
        isA<InsufficientFrameDataException>(),
        reason: 'a zero-frame capture must throw, not return all zeros',
      );
    });

    testWidgets('the exception explains the likely cause', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Text('hi')));

      try {
        await measureScreenPerformance(
          scenario: 'never_measured',
          action: () async {
            await tester.pump();
          },
        );
        fail('expected InsufficientFrameDataException');
      } on InsufficientFrameDataException catch (e) {
        expect(e.sampledFrameCount, 0);
        expect(e.scenario, 'never_measured');
        expect(e.toString(), contains('integration_test'));
      }
    });
  });

  group('PerfComparator', () {
    test('fails instead of passing when the current run captured no frames',
        () {
      final result = const PerfComparator().compare(
        baseline: _summary(const [4, 5, 6, 7, 8]),
        current: _summary(const []),
      );

      expect(
        result.passed,
        isFalse,
        reason: 'an empty current run must never report a clean pass',
      );
      expect(result.errors, isNotEmpty);
      expect(result.errors.join(), contains('current run captured 0 frames'));
    });

    test('fails when the committed baseline itself is empty', () {
      final result = const PerfComparator().compare(
        baseline: _summary(const []),
        current: _summary(const [4, 5, 6, 7, 8]),
      );

      expect(result.passed, isFalse);
      expect(result.errors.join(), contains('baseline captured 0 frames'));
    });

    test('empty-vs-empty is a failure, not a perfect match', () {
      final result = const PerfComparator().compare(
        baseline: _summary(const []),
        current: _summary(const []),
      );

      expect(result.passed, isFalse);
      expect(result.errors.length, 2);
    });

    test('a real capture still compares normally', () {
      final result = const PerfComparator().compare(
        baseline: _summary(const [4, 5, 6, 7, 8]),
        current: _summary(const [4, 5, 6, 7, 8]),
      );

      expect(result.passed, isTrue);
      expect(result.errors, isEmpty);
      expect(result.checks, isNotEmpty);
    });
  });

  group('gradeSummary', () {
    test('grades an empty capture unknown rather than good', () {
      expect(gradeSummary(_summary(const [])), PerfGrade.unknown);
    });

    test('still grades a genuinely fast capture good', () {
      expect(gradeSummary(_summary(const [4, 5, 6])), PerfGrade.good);
    });
  });
}
