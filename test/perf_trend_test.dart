// Tests for cumulative drift detection.
//
// The case that motivates all of this: a run of changes that each pass the
// baseline gate comfortably, but which together leave a screen far slower than
// it started. No single baseline comparison can see that, because after each
// accepted change the baseline moves with it.

// dart format off
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show
        PerfComparator,
        PerfHistory,
        PerfHistoryEntry,
        PerfSummary,
        analyzeDrift,
        encodeHistoryEntries,
        formatDriftRatio,
        parseHistory;
// dart format on

PerfSummary _summary(double millis, {String scenario = 'demo'}) =>
    PerfSummary.fromDurations(
      scenario: scenario,
      buildMillis: [millis, millis, millis],
      rasterMillis: const [1, 1, 1],
      frameBudgetMillis: 16.67,
    );

PerfHistoryEntry _entry(double millis,
        {String scenario = 'demo', int day = 1}) =>
    PerfHistoryEntry(
      recordedAt: DateTime.utc(2026, 1, day),
      summary: _summary(millis, scenario: scenario),
      label: 'sha$day',
    );

List<PerfHistoryEntry> _historyOf(List<double> values) => [
      for (var i = 0; i < values.length; i++) _entry(values[i], day: i + 1),
    ];

void main() {
  group('analyzeDrift', () {
    test('returns null until there are enough runs to call it a trend', () {
      expect(
        analyzeDrift(history: _historyOf([4, 4]), current: _summary(40)),
        isNull,
        reason: 'two runs is not a trend',
      );
    });

    test('anchors to the median of the oldest runs, not the newest', () {
      final drift = analyzeDrift(
        history: _historyOf([4, 4, 4, 100, 100]),
        current: _summary(4),
      )!;

      // Anchored to the old, fast runs — so a current run matching them has
      // not drifted, despite recent history being slow.
      expect(drift.reference.build.p90, 4);
      expect(drift.drifted, isFalse);
    });

    test('reports the fractional change since the reference', () {
      final drift = analyzeDrift(
        history: _historyOf([10, 10, 10]),
        current: _summary(15),
      )!;

      expect(drift.buildP90DriftRatio, closeTo(0.5, 1e-9));
      expect(drift.totalSampleCount, 3);
      expect(drift.referenceSampleCount, 3);
    });

    test('reports improvement as negative drift', () {
      final drift = analyzeDrift(
        history: _historyOf([10, 10, 10]),
        current: _summary(5),
      )!;

      expect(drift.buildP90DriftRatio, closeTo(-0.5, 1e-9));
      expect(drift.drifted, isFalse);
    });

    test('catches creep that every individual comparison let through', () {
      // Each step is a ~12% regression: inside the default +15% p90 gate, so
      // every one of these changes would have shipped green.
      final steps = <double>[4.0, 4.5, 5.0, 5.6, 6.3, 7.1, 7.9];
      for (var i = 1; i < steps.length; i++) {
        final stepGate = const PerfComparator().compare(
          baseline: _summary(steps[i - 1]),
          current: _summary(steps[i]),
        );
        expect(stepGate.passed, isTrue,
            reason: 'step ${steps[i - 1]} -> ${steps[i]} must pass the gate');
      }

      // Yet the total is a doubling, and drift sees it.
      final drift = analyzeDrift(
        history: _historyOf(steps.sublist(0, 3)),
        current: _summary(steps.last),
      )!;

      expect(drift.drifted, isTrue);
      expect(drift.buildP90DriftRatio, greaterThan(0.5));
    });

    test('tolerates drift below the threshold', () {
      // +20% total is real but under the 50% cumulative allowance.
      final drift = analyzeDrift(
        history: _historyOf([10, 10, 10]),
        current: _summary(12),
      )!;

      expect(drift.drifted, isFalse);
    });

    test('uses the worse of build and raster for the headline ratio', () {
      final history = [
        for (var i = 0; i < 3; i++)
          PerfHistoryEntry(
            recordedAt: DateTime.utc(2026, 1, i + 1),
            summary: PerfSummary.fromDurations(
              scenario: 'demo',
              buildMillis: const [10, 10, 10],
              rasterMillis: const [10, 10, 10],
              frameBudgetMillis: 16.67,
            ),
          ),
      ];
      final current = PerfSummary.fromDurations(
        scenario: 'demo',
        buildMillis: const [10, 10, 10], // unchanged
        rasterMillis: const [20, 20, 20], // doubled
        frameBudgetMillis: 16.67,
      );

      final drift = analyzeDrift(history: history, current: current)!;
      expect(drift.worstP90DriftRatio, closeTo(1.0, 1e-9));
      expect(drift.drifted, isTrue);
    });
  });

  group('history round-trip', () {
    test('encodes and parses entries losslessly', () {
      final encoded = encodeHistoryEntries(_historyOf([4, 5, 6]));
      final parsed = parseHistory(encoded);

      expect(parsed.errors, isEmpty);
      expect(parsed.entries, hasLength(3));
      expect(parsed.entries.first.label, 'sha1');
      expect(parsed.entries.first.summary.build.p90, 4);
      expect(parsed.entries.first.recordedAt, DateTime.utc(2026, 1, 1));
    });

    test('every line is terminated so appends stay well-formed', () {
      final a = encodeHistoryEntries(_historyOf([4]));
      final b = encodeHistoryEntries(_historyOf([5]));

      expect(parseHistory(a + b).entries, hasLength(2));
    });

    test('one corrupt line does not lose the rest of the history', () {
      final good = encodeHistoryEntries(_historyOf([4, 5]));
      final parsed = parseHistory('$good{ this is not json\n');

      expect(parsed.entries, hasLength(2));
      expect(parsed.errors, hasLength(1));
    });

    test('ignores blank lines', () {
      expect(parseHistory('\n\n  \n').entries, isEmpty);
      expect(parseHistory('\n\n  \n').errors, isEmpty);
    });

    test('separates scenarios', () {
      final mixed = encodeHistoryEntries([
        _entry(4, scenario: 'a'),
        _entry(5, scenario: 'b'),
        _entry(6, scenario: 'a'),
      ]);
      final history = parseHistory(mixed);

      expect(history.scenarios, ['a', 'b']);
      expect(history.forScenario('a'), hasLength(2));
      expect(history.forScenario('b'), hasLength(1));
    });

    test('exposes an empty history cleanly', () {
      const empty = PerfHistory(entries: [], errors: []);
      expect(empty.forScenario('demo'), isEmpty);
      expect(empty.scenarios, isEmpty);
    });
  });

  group('formatDriftRatio', () {
    test('signs the percentage', () {
      expect(formatDriftRatio(0.42), '+42%');
      expect(formatDriftRatio(-0.08), '-8%');
      expect(formatDriftRatio(0), '+0%');
    });

    test('renders an unmeasurable ratio as n/a', () {
      expect(formatDriftRatio(double.infinity), 'n/a');
    });
  });
}
