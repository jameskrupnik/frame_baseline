// dart format off
import 'dart:async' show ZoneSpecification, runZoned;
import 'dart:convert' show jsonEncode;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show
        PerfSummary,
        extractPerfSummaries,
        kPerfSummaryMarker,
        reportPerfSummary;
// dart format on

String _line(PerfSummary s, {String prefix = ''}) =>
    '$prefix$kPerfSummaryMarker${jsonEncode(s.toJson())}';

PerfSummary _summary(String scenario) => PerfSummary.fromDurations(
      scenario: scenario,
      buildMillis: const [4, 5, 6],
      rasterMillis: const [4, 5, 6],
      frameBudgetMillis: 16.67,
    );

void main() {
  group('extractPerfSummaries', () {
    test('parses every marked line in order', () {
      final log = [
        'some device noise',
        _line(_summary('home')),
        'more noise',
        _line(_summary('chat')),
      ].join('\n');

      final result = extractPerfSummaries(log);
      expect(result.errors, isEmpty);
      expect(
        result.summaries.map((s) => s.scenario),
        ['home', 'chat'],
      );
    });

    test('ignores any prefix before the marker (e.g. a log timestamp)', () {
      final log = _line(
        _summary('home'),
        prefix: '2026-07-19 12:00:00.123 I/flutter: ',
      );
      final result = extractPerfSummaries(log);
      expect(result.summaries.single.scenario, 'home');
    });

    test('collects errors for marked-but-unparsable lines, keeps the rest', () {
      final log = [
        '${kPerfSummaryMarker}not valid json',
        _line(_summary('good')),
      ].join('\n');

      final result = extractPerfSummaries(log);
      expect(result.summaries.single.scenario, 'good');
      expect(result.errors, hasLength(1));
      expect(result.errors.single, contains('unparsable'));
    });

    test('collects errors for valid JSON of the wrong shape', () {
      // Valid JSON that is not a summary used to escape as a TypeError from
      // an `as` cast and abort the whole extraction.
      final log = [
        '$kPerfSummaryMarker[1, 2, 3]',
        '$kPerfSummaryMarker{"scenario": 7}',
        _line(_summary('good')),
      ].join('\n');

      final result = extractPerfSummaries(log);
      expect(result.summaries.single.scenario, 'good');
      expect(result.errors, hasLength(2));
      expect(result.errors.last, contains('"scenario"'));
    });

    test('returns empty when no marker is present', () {
      final result = extractPerfSummaries('nothing to see here\njust logs');
      expect(result.summaries, isEmpty);
      expect(result.errors, isEmpty);
    });
  });

  group('reportPerfSummary', () {
    test('prints one line that extractPerfSummaries reads back', () {
      final printed = <String>[];
      runZoned(
        () => reportPerfSummary(_summary('home')),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, line) => printed.add(line),
        ),
      );

      expect(printed, hasLength(1));
      final result = extractPerfSummaries(printed.single);
      expect(result.errors, isEmpty);
      expect(result.summaries.single.toJson(), _summary('home').toJson());
    });
  });
}
