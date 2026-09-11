// dart format off
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show
        PerfComparator,
        PerfGrade,
        PerfSummary,
        RegressionStatus,
        ScenarioReport,
        gradeSummary,
        regressionStatusFor,
        renderHtmlReport,
        renderTerminalSummary;
// dart format on

PerfSummary _summary({
  required List<double> buildMillis,
  String scenario = 'demo',
  List<double>? rasterMillis,
}) {
  return PerfSummary.fromDurations(
    scenario: scenario,
    buildMillis: buildMillis,
    rasterMillis: rasterMillis ?? buildMillis,
    frameBudgetMillis: 16.67,
  );
}

void main() {
  group('gradeSummary', () {
    test('good when well under budget with no jank', () {
      expect(gradeSummary(_summary(buildMillis: [4, 5, 6])), PerfGrade.good);
    });

    test('ok when approaching budget', () {
      // p90 ~12ms sits between 50% and 100% of the 16.67ms budget.
      expect(gradeSummary(_summary(buildMillis: [11, 12, 12])), PerfGrade.ok);
    });

    test('poor when a thread is over budget', () {
      expect(gradeSummary(_summary(buildMillis: [4, 4, 40])), PerfGrade.poor);
    });

    test('graded on the worse of build and raster', () {
      final s = _summary(
        buildMillis: [4, 4, 4], // build alone would be good
        rasterMillis: [4, 4, 40], // raster drags it to poor
      );
      expect(gradeSummary(s), PerfGrade.poor);
    });
  });

  group('regressionStatusFor', () {
    const comparator = PerfComparator();

    test('noBaseline when comparison is null', () {
      expect(regressionStatusFor(null), RegressionStatus.noBaseline);
    });

    test('pass when comfortably within tolerance', () {
      final c = comparator.compare(
        baseline: _summary(buildMillis: [4, 5, 6, 7, 8]),
        current: _summary(buildMillis: [4, 5, 6, 7, 8]),
      );
      expect(regressionStatusFor(c), RegressionStatus.pass);
    });

    test('nearLimit when a metric is close to its limit but passing', () {
      // build.p90 baseline 10 -> limit 11.5 (+15%); current 11 is ~0.96 of it.
      final c = comparator.compare(
        baseline: _summary(buildMillis: [10, 10, 10, 10, 10]),
        current: _summary(buildMillis: [11, 11, 11, 11, 11]),
      );
      expect(c.passed, isTrue);
      expect(regressionStatusFor(c), RegressionStatus.nearLimit);
    });

    test('regressed when a metric fails', () {
      final c = comparator.compare(
        baseline: _summary(buildMillis: [4, 4, 4, 4, 8]),
        current: _summary(buildMillis: [4, 4, 4, 4, 40]),
      );
      expect(regressionStatusFor(c), RegressionStatus.regressed);
    });
  });

  group('renderTerminalSummary', () {
    test('omits ANSI codes when colored is false', () {
      final out = renderTerminalSummary(
        [
          ScenarioReport(summary: _summary(buildMillis: [4, 5, 6])),
        ],
        colored: false,
      );
      expect(out, contains('demo'));
      expect(out, contains('good'));
      expect(out, isNot(contains('\x1b[')));
    });

    test('includes ANSI codes when colored is true', () {
      final out = renderTerminalSummary(
        [
          ScenarioReport(summary: _summary(buildMillis: [4, 4, 40])),
        ],
        colored: true,
      );
      expect(out, contains('\x1b[')); // some color emitted
    });

    test('is empty for no reports', () {
      expect(renderTerminalSummary([], colored: true), isEmpty);
    });
  });

  group('renderHtmlReport', () {
    test('renders a row per screen with grade and status classes', () {
      const comparator = PerfComparator();
      final good = ScenarioReport(summary: _summary(buildMillis: [4, 5, 6]));
      final bad = ScenarioReport(
        summary: _summary(scenario: 'janky', buildMillis: [40, 40, 40]),
        comparison: comparator.compare(
          baseline: _summary(scenario: 'janky', buildMillis: [4, 4, 4]),
          current: _summary(scenario: 'janky', buildMillis: [40, 40, 40]),
        ),
      );
      final html = renderHtmlReport([good, bad], generatedAtIso: '2026-01-01');

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Generated 2026-01-01'));
      expect(html, contains('demo'));
      expect(html, contains('class="badge good"'));
      expect(html, contains('class="badge poor"'));
      expect(html, contains('REGRESSED'));
    });

    test('escapes scenario names', () {
      final html = renderHtmlReport([
        ScenarioReport(
          summary: _summary(scenario: '<x>&"', buildMillis: [4, 5, 6]),
        ),
      ]);
      expect(html, contains('&lt;x&gt;&amp;&quot;'));
      expect(html, isNot(contains('<x>&"')));
    });
  });
}
