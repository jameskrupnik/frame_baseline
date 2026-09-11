// dart format off
import 'dart:convert' show jsonEncode;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show PerfSummary, extractPerfSummaries, kPerfSummaryMarker;
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

    test('returns empty when no marker is present', () {
      final result = extractPerfSummaries('nothing to see here\njust logs');
      expect(result.summaries, isEmpty);
      expect(result.errors, isEmpty);
    });
  });
}
