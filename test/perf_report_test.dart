// dart format off
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart'
    show
        PerfCheck,
        PerfComparator,
        PerfComparison,
        PerfGrade,
        PerfHistoryEntry,
        PerfSummary,
        PerfTolerance,
        RegressionStatus,
        ScenarioReport,
        analyzeDrift,
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

    test('nearLimit when a metric has used most of its headroom', () {
      // build.p90 baseline 10 -> limit 11.5 (+15%); 11.4 has used 93% of the
      // 1.5ms of headroom above the baseline.
      final c = comparator.compare(
        baseline: _summary(buildMillis: [10, 10, 10, 10, 10]),
        current: _summary(buildMillis: [11.4, 11.4, 11.4, 11.4, 11.4]),
      );
      expect(c.passed, isTrue);
      expect(regressionStatusFor(c), RegressionStatus.nearLimit);
    });

    test('pass when a metric has used under 90% of its headroom', () {
      // 11 has used 67% of the 1.5ms of headroom; nearness is measured from
      // the baseline, not from zero.
      final c = comparator.compare(
        baseline: _summary(buildMillis: [10, 10, 10, 10, 10]),
        current: _summary(buildMillis: [11, 11, 11, 11, 11]),
      );
      expect(regressionStatusFor(c), RegressionStatus.pass);
    });

    test('a run identical to its baseline is never nearLimit', () {
      // Measured on a Pixel 7 Pro: a capture compared against baselines
      // written from itself read "near-limit". A janky screen's missed-frame
      // limit is its own count plus a 2-frame slack, so 30 missed frames sit
      // at 94% of a limit of 32 before anything has changed.
      final same = _summary(
        buildMillis: [for (var i = 0; i < 40; i++) i < 30 ? 20 : 4],
      );
      final c = comparator.compare(baseline: same, current: same);
      expect(regressionStatusFor(c), RegressionStatus.pass);
    });

    test('a faster run is never nearLimit', () {
      final c = comparator.compare(
        baseline: _summary(buildMillis: [20, 22, 24, 26, 28]),
        current: _summary(buildMillis: [19, 21, 23, 25, 27]),
      );
      expect(regressionStatusFor(c), RegressionStatus.pass);
    });

    test('zero headroom: unchanged passes, it is not near its limit', () {
      const strict = PerfComparator(
        tolerance: PerfTolerance(
          maxP90BuildRegressionRatio: 0,
          maxP99BuildRegressionRatio: 0,
          maxWorstBuildRegressionRatio: 0,
          maxP90RasterRegressionRatio: 0,
          maxP99RasterRegressionRatio: 0,
          maxWorstRasterRegressionRatio: 0,
          maxAdditionalJankyFrameRatio: 0,
          jankyFrameSlack: 0,
          absoluteSlackMillis: 0,
        ),
      );
      final same = _summary(buildMillis: [20, 22, 24, 26, 28]);
      final c = strict.compare(baseline: same, current: same);
      expect(c.passed, isTrue);
      expect(regressionStatusFor(c), RegressionStatus.pass);
    });

    test('zero baseline: near only once most of the slack is used', () {
      // A baseline with no janky frames gets a limit of the 2-frame slack.
      RegressionStatus statusAt(double current) => regressionStatusFor(
            PerfComparison(
              scenario: 'demo',
              checks: [
                PerfCheck(
                  name: 'missedBuildBudgetCount',
                  baseline: 0,
                  current: current,
                  limit: 2,
                  passed: current <= 2,
                ),
              ],
            ),
          );
      expect(statusAt(0), RegressionStatus.pass);
      expect(statusAt(1), RegressionStatus.pass);
      expect(statusAt(2), RegressionStatus.nearLimit);
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
      final html =
          renderHtmlReport([good, bad], generatedAt: DateTime.utc(2026));

      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('Generated 2026-01-01'));
      expect(html, contains('demo'));
      expect(html, contains('class="badge good"'));
      expect(html, contains('class="badge poor"'));
      expect(html, contains('REGRESSED'));
    });

    test('does not claim a 60fps budget for a 120 Hz capture', () {
      final html = renderHtmlReport([
        ScenarioReport(
          summary: PerfSummary.fromDurations(
            scenario: 'fast_phone',
            buildMillis: const [4, 5, 6],
            rasterMillis: const [4, 5, 6],
            frameBudgetMillis: 1000 / 120,
          ),
        ),
      ]);
      expect(html, isNot(contains('60fps')));
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

  group('PerfGrade', () {
    test('tryParse accepts threshold names, ignoring case and whitespace', () {
      expect(PerfGrade.tryParse('good'), PerfGrade.good);
      expect(PerfGrade.tryParse(' OK '), PerfGrade.ok);
      expect(PerfGrade.tryParse('Poor'), PerfGrade.poor);
    });

    test('tryParse rejects unknown names, including "unknown"', () {
      expect(PerfGrade.tryParse('blazing'), isNull);
      expect(PerfGrade.tryParse('unknown'), isNull);
    });

    test('severity orders healthiest to worst, with unknown last', () {
      final ranked = [...PerfGrade.values]
        ..sort((a, b) => a.severity.compareTo(b.severity));
      expect(ranked, [
        PerfGrade.good,
        PerfGrade.ok,
        PerfGrade.poor,
        PerfGrade.unknown,
      ]);
    });
  });

  group('drift and unmeasured screens', () {
    // Three fast runs anchor the history; a much slower current run drifts.
    final history = [
      for (var day = 1; day <= 3; day++)
        PerfHistoryEntry(
          recordedAt: DateTime.utc(2026, 1, day),
          summary: _summary(buildMillis: [4, 4, 4]),
        ),
    ];
    final slow = _summary(buildMillis: [12, 12, 12]);
    final drifted = ScenarioReport(
      summary: slow,
      drift: analyzeDrift(history: history, current: slow),
    );
    final steady = ScenarioReport(
      summary: _summary(buildMillis: [4, 4, 4]),
      drift: analyzeDrift(
        history: history,
        current: _summary(buildMillis: [4, 4, 4]),
      ),
    );
    final unmeasured = ScenarioReport(
      summary: _summary(scenario: 'dead', buildMillis: []),
    );

    test('the terminal summary shows drift and explains drifted screens', () {
      final out = renderTerminalSummary([drifted, steady], colored: true);

      expect(out, contains('+200%'));
      expect(out, contains('+0%'));
      expect(out, contains('DRIFT since history began'));
      expect(out, contains('median of its first 3 of 3 recorded runs'));
    });

    test('the terminal summary labels an unmeasured screen n/a', () {
      final out = renderTerminalSummary([unmeasured], colored: true);

      expect(out, contains('n/a'));
      expect(out, isNot(contains('good')));
    });

    test('the HTML report colors drift cells by whether they drifted', () {
      final html = renderHtmlReport([drifted, steady]);

      expect(
        html,
        contains('<td class="poor" title="vs median of first 3 of 3 '
            'recorded runs">+200%</td>'),
      );
      expect(html, contains('<td class="good" title="vs median'));
    });

    test('the HTML report never badges an unmeasured screen good', () {
      final html = renderHtmlReport([unmeasured]);

      expect(html, contains('<td class="badge poor">n/a</td>'));
    });
  });
}
