// dart format off
import 'dart:math' as math show max;

import 'package:frame_baseline/src/perf_comparator.dart' show PerfComparison;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
import 'package:frame_baseline/src/perf_trend.dart' show PerfDrift;
// dart format on

/// Absolute performance grade for a single screen, judged against the frame
/// budget — independent of any baseline. Answers "is this screen fast?".
enum PerfGrade {
  /// Comfortably smooth: p90 well under budget and almost no janky frames.
  good,

  /// Acceptable but watch it: approaching budget or some janky frames.
  ok,

  /// Janky: a p90 over budget or a meaningful share of missed frames.
  poor,

  /// No frames were captured, so the screen's performance is simply unknown.
  /// Distinct from [good]: an empty capture has zero for every metric, and
  /// grading that as flawless is how a broken measurement masquerades as a
  /// healthy one.
  unknown,
}

/// Regression verdict for a screen relative to its committed baseline.
/// Answers "did this change make it worse?".
enum RegressionStatus {
  /// Comfortably within tolerance.
  pass,

  /// Passing, but a metric is within [kNearLimitFraction] of its limit.
  nearLimit,

  /// At least one metric regressed past tolerance.
  regressed,

  /// No baseline to compare against (e.g. first run / `--update`).
  noBaseline,
}

/// A screen's absolute grade is `good` while its worst-thread p90 stays under
/// this fraction of the frame budget (and jank stays under [kGoodJankRatio]).
const double kGoodP90BudgetFraction = 0.5;

/// Above [kGoodP90BudgetFraction] but at/under this fraction of budget grades
/// `ok`; a p90 over this is `poor`.
const double kOkP90BudgetFraction = 1.0;

/// Max janky-frame fraction still allowed for a `good` grade (1%).
const double kGoodJankRatio = 0.01;

/// Max janky-frame fraction still allowed for an `ok` grade (5%).
const double kOkJankRatio = 0.05;

/// A passing metric this close to its limit (as a fraction) is flagged
/// [RegressionStatus.nearLimit] rather than [RegressionStatus.pass].
const double kNearLimitFraction = 0.9;

/// Orders grades from healthiest to worst, so callers can express thresholds
/// like "fail if anything is `poor` or worse".
///
/// [PerfGrade.unknown] ranks worst: a screen we failed to measure is never
/// evidence that the screen is fine.
int gradeSeverity(PerfGrade grade) => switch (grade) {
      PerfGrade.good => 0,
      PerfGrade.ok => 1,
      PerfGrade.poor => 2,
      PerfGrade.unknown => 3,
    };

/// Parses a grade threshold name (`good`, `ok`, `poor`) for CLI use, or null if
/// [name] isn't one.
PerfGrade? parseGrade(String name) => switch (name.trim().toLowerCase()) {
      'good' => PerfGrade.good,
      'ok' => PerfGrade.ok,
      'poor' => PerfGrade.poor,
      _ => null,
    };

/// Grades [summary] on absolute performance against its own frame budget.
///
/// Uses the worse of the build and raster threads for both the p90 and the
/// janky-frame fraction, so a screen is only as good as its slowest thread.
PerfGrade gradeSummary(PerfSummary summary) {
  if (summary.sampledFrameCount <= 0) return PerfGrade.unknown;
  final budget = summary.frameBudgetMillis;
  final p90 = math.max(summary.build.p90, summary.raster.p90);
  final jank = math.max(
    summary.jankyBuildFrameRatio,
    summary.jankyRasterFrameRatio,
  );
  final p90Fraction = budget <= 0 ? double.infinity : p90 / budget;

  if (p90Fraction <= kGoodP90BudgetFraction && jank <= kGoodJankRatio) {
    return PerfGrade.good;
  }
  if (p90Fraction <= kOkP90BudgetFraction && jank <= kOkJankRatio) {
    return PerfGrade.ok;
  }
  return PerfGrade.poor;
}

/// Derives a [RegressionStatus] from a comparison, or [RegressionStatus.noBaseline]
/// when [comparison] is null.
RegressionStatus regressionStatusFor(PerfComparison? comparison) {
  if (comparison == null) return RegressionStatus.noBaseline;
  if (!comparison.passed) return RegressionStatus.regressed;
  for (final check in comparison.checks) {
    if (check.limit > 0 && check.current >= check.limit * kNearLimitFraction) {
      return RegressionStatus.nearLimit;
    }
  }
  return RegressionStatus.pass;
}

/// One screen's line in the cross-screen report: its current [summary], the
/// absolute [grade], and — when a baseline existed — the [status] and raw
/// [comparison].
class ScenarioReport {
  ScenarioReport({required this.summary, this.comparison, this.drift})
      : grade = gradeSummary(summary),
        status = regressionStatusFor(comparison);

  /// The current run's summary for this screen.
  final PerfSummary summary;

  /// The baseline comparison, or null if there was no baseline.
  final PerfComparison? comparison;

  /// Cumulative drift since the scenario's history began, or null when history
  /// is absent or too short to judge.
  final PerfDrift? drift;

  /// Absolute performance grade (baseline-independent).
  final PerfGrade grade;

  /// Regression verdict relative to the baseline.
  final RegressionStatus status;
}

/// Absolute threshold bucket for a single frame-time metric (ms), used to color
/// individual cells. Mirrors [gradeSummary]'s per-metric logic.
PerfGrade gradeMillis(double millis, double budget) {
  final fraction = budget <= 0 ? double.infinity : millis / budget;
  if (fraction <= kGoodP90BudgetFraction) return PerfGrade.good;
  if (fraction <= kOkP90BudgetFraction) return PerfGrade.ok;
  return PerfGrade.poor;
}

/// Absolute threshold bucket for a janky-frame fraction (0..1).
PerfGrade gradeJankRatio(double ratio) {
  if (ratio <= kGoodJankRatio) return PerfGrade.good;
  if (ratio <= kOkJankRatio) return PerfGrade.ok;
  return PerfGrade.poor;
}

// ---------------------------------------------------------------------------
// Terminal rendering
// ---------------------------------------------------------------------------

const _ansiReset = '\x1b[0m';
const _ansiGreen = '\x1b[32m';
const _ansiYellow = '\x1b[33m';
const _ansiRed = '\x1b[31m';
const _ansiGray = '\x1b[90m';
const _ansiBold = '\x1b[1m';

String _gradeColor(PerfGrade g) => switch (g) {
      PerfGrade.good => _ansiGreen,
      PerfGrade.ok => _ansiYellow,
      PerfGrade.poor => _ansiRed,
      PerfGrade.unknown => _ansiRed,
    };

String _gradeLabel(PerfGrade g) => switch (g) {
      PerfGrade.good => 'good',
      PerfGrade.ok => 'ok',
      PerfGrade.poor => 'poor',
      PerfGrade.unknown => 'n/a',
    };

String _statusColor(RegressionStatus s) => switch (s) {
      RegressionStatus.pass => _ansiGreen,
      RegressionStatus.nearLimit => _ansiYellow,
      RegressionStatus.regressed => _ansiRed,
      RegressionStatus.noBaseline => _ansiGray,
    };

String _statusLabel(RegressionStatus s) => switch (s) {
      RegressionStatus.pass => 'ok',
      RegressionStatus.nearLimit => 'near-limit',
      RegressionStatus.regressed => 'REGRESSED',
      RegressionStatus.noBaseline => 'no baseline',
    };

String _paint(String text, String color, {required bool colored}) =>
    colored ? '$color$text$_ansiReset' : text;

/// Renders a cross-screen summary table for the terminal. Pass `colored: false`
/// when stdout is not a TTY (or `NO_COLOR` is set) to get plain text.
String renderTerminalSummary(
  List<ScenarioReport> reports, {
  required bool colored,
}) {
  if (reports.isEmpty) return '';
  final scenarioWidth = reports
      .map((r) => r.summary.scenario.length)
      .fold(8, (a, b) => math.max(a, b));

  final buf = StringBuffer();
  final title = 'PERF SUMMARY (${reports.length} '
      'screen${reports.length == 1 ? '' : 's'})';
  buf.writeln();
  buf.writeln(_paint(title, _ansiBold, colored: colored));

  for (final r in reports) {
    final s = r.summary;
    final name = s.scenario.padRight(scenarioWidth);
    final grade = _paint(
      _gradeLabel(r.grade).padRight(4),
      _gradeColor(r.grade),
      colored: colored,
    );
    final status = _paint(
      _statusLabel(r.status).padRight(11),
      _statusColor(r.status),
      colored: colored,
    );
    final jank = math.max(s.jankyBuildFrameRatio, s.jankyRasterFrameRatio);
    final drift = r.drift == null
        ? ''
        : '  drift=${_paint(
            formatDriftRatio(r.drift!.worstP90DriftRatio),
            r.drift!.drifted ? _ansiRed : _ansiGray,
            colored: colored,
          )}';
    buf.writeln(
      '  $name  $grade  $status  '
      'build.p90=${s.build.p90.toStringAsFixed(1)}ms  '
      'raster.p90=${s.raster.p90.toStringAsFixed(1)}ms  '
      'jank=${(jank * 100).toStringAsFixed(1)}%$drift',
    );
  }

  final drifted = reports.where((r) => r.drift?.drifted ?? false).toList();
  if (drifted.isNotEmpty) {
    buf.writeln();
    buf.writeln(
      _paint('DRIFT since history began', _ansiBold, colored: colored),
    );
    for (final r in drifted) {
      final d = r.drift!;
      buf.writeln(
        '  ${r.summary.scenario} is '
        '${formatDriftRatio(d.worstP90DriftRatio)} vs the median of its first '
        '${d.referenceSampleCount} of ${d.totalSampleCount} recorded runs.',
      );
    }
    buf.writeln(
      '  Cumulative since tracking began; may be one regression or many '
      'individually-passing changes adding up.',
    );
  }
  return buf.toString();
}

/// Formats a drift ratio as a signed percentage, e.g. `+42%` or `-8%`.
String formatDriftRatio(double ratio) {
  if (ratio.isInfinite) return 'n/a';
  final pct = ratio * 100;
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(0)}%';
}

// ---------------------------------------------------------------------------
// HTML rendering
// ---------------------------------------------------------------------------

String _htmlEscape(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

String _gradeClass(PerfGrade g) => switch (g) {
      PerfGrade.good => 'good',
      PerfGrade.ok => 'ok',
      PerfGrade.poor => 'poor',
      PerfGrade.unknown => 'poor',
    };

String _statusClass(RegressionStatus s) => switch (s) {
      RegressionStatus.pass => 'good',
      RegressionStatus.nearLimit => 'ok',
      RegressionStatus.regressed => 'poor',
      RegressionStatus.noBaseline => 'none',
    };

String _millisCell(double millis, double budget) {
  final cls = _gradeClass(gradeMillis(millis, budget));
  return '<td class="$cls">${millis.toStringAsFixed(1)}</td>';
}

String _jankCell(double ratio) {
  final cls = _gradeClass(gradeJankRatio(ratio));
  return '<td class="$cls">${(ratio * 100).toStringAsFixed(1)}%</td>';
}

/// Cumulative-drift cell. Blank-styled when there is no history yet, since
/// "unknown" and "no drift" are different claims.
String _driftCell(PerfDrift? drift) {
  if (drift == null) return '<td class="none">&mdash;</td>';
  final cls = drift.drifted ? 'poor' : 'good';
  final title = 'vs median of first ${drift.referenceSampleCount} of '
      '${drift.totalSampleCount} recorded runs';
  return '<td class="$cls" title="${_htmlEscape(title)}">'
      '${formatDriftRatio(drift.worstP90DriftRatio)}</td>';
}

/// Renders a standalone, self-contained HTML report of all screens, with cells
/// color-coded by absolute performance and a per-screen regression status.
///
/// [generatedAtIso] is embedded verbatim in the header (pass an ISO-8601
/// timestamp, or null to omit).
String renderHtmlReport(
  List<ScenarioReport> reports, {
  String? generatedAtIso,
}) {
  final rows = StringBuffer();
  for (final r in reports) {
    final s = r.summary;
    final b = s.build;
    final ras = s.raster;
    rows.writeln('''
      <tr>
        <td class="scenario">${_htmlEscape(s.scenario)}</td>
        <td class="badge ${_gradeClass(r.grade)}">${_gradeLabel(r.grade)}</td>
        <td class="badge ${_statusClass(r.status)}">${_statusLabel(r.status)}</td>
        ${_millisCell(b.p90, s.frameBudgetMillis)}
        ${_millisCell(b.p99, s.frameBudgetMillis)}
        ${_millisCell(b.worst, s.frameBudgetMillis)}
        ${_millisCell(ras.p90, s.frameBudgetMillis)}
        ${_millisCell(ras.p99, s.frameBudgetMillis)}
        ${_millisCell(ras.worst, s.frameBudgetMillis)}
        ${_jankCell(s.jankyBuildFrameRatio)}
        ${_jankCell(s.jankyRasterFrameRatio)}
        <td class="num">${s.sampledFrameCount}</td>
        ${_driftCell(r.drift)}
      </tr>''');
  }

  final generated = generatedAtIso == null
      ? ''
      : '<p class="meta">Generated ${_htmlEscape(generatedAtIso)}</p>';

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>frame_baseline &middot; performance report</title>
<style>
  :root {
    --good-bg: #e6f4ea; --good-fg: #137333;
    --ok-bg:   #fef7e0; --ok-fg:   #b06000;
    --poor-bg: #fce8e6; --poor-fg: #c5221f;
    --none-bg: #f1f3f4; --none-fg: #5f6368;
  }
  body { font: 14px/1.5 -apple-system, Segoe UI, Roboto, sans-serif;
         color: #202124; margin: 2rem; background: #fff; }
  h1 { font-size: 1.3rem; margin: 0 0 .25rem; }
  .meta { color: #5f6368; margin: 0 0 1.25rem; }
  table { border-collapse: collapse; width: 100%; font-variant-numeric: tabular-nums; }
  th, td { padding: .45rem .6rem; text-align: right; border-bottom: 1px solid #eee; }
  th { text-align: right; color: #5f6368; font-weight: 600; white-space: nowrap;
       border-bottom: 2px solid #ddd; position: sticky; top: 0; background: #fff; }
  th.scenario, td.scenario { text-align: left; font-weight: 600; }
  .group { border-left: 1px solid #eee; }
  td.good  { background: var(--good-bg); color: var(--good-fg); }
  td.ok    { background: var(--ok-bg);   color: var(--ok-fg); }
  td.poor  { background: var(--poor-bg); color: var(--poor-fg); font-weight: 600; }
  td.none  { background: var(--none-bg); color: var(--none-fg); }
  .badge { text-align: center; font-weight: 600; text-transform: uppercase;
           font-size: .72rem; letter-spacing: .03em; }
  .legend { margin: 1.25rem 0 0; color: #5f6368; font-size: .85rem; }
  .legend span { display: inline-block; padding: .1rem .5rem; border-radius: 3px;
                 margin-right: .4rem; }
  .legend .good { background: var(--good-bg); color: var(--good-fg); }
  .legend .ok   { background: var(--ok-bg);   color: var(--ok-fg); }
  .legend .poor { background: var(--poor-bg); color: var(--poor-fg); }
</style>
</head>
<body>
<h1>frame_baseline &middot; performance report</h1>
$generated
<table>
  <thead>
    <tr>
      <th class="scenario">Screen</th>
      <th>Grade</th>
      <th>vs baseline</th>
      <th class="group">build p90</th>
      <th>build p99</th>
      <th>build worst</th>
      <th class="group">raster p90</th>
      <th>raster p99</th>
      <th>raster worst</th>
      <th class="group">build jank</th>
      <th>raster jank</th>
      <th class="group">frames</th>
      <th>drift</th>
    </tr>
  </thead>
  <tbody>
$rows  </tbody>
</table>
<p class="legend">
  Cell color = absolute performance vs the 60fps budget:
  <span class="good">good</span> &lt;50% of budget
  <span class="ok">ok</span> 50&ndash;100%
  <span class="poor">poor</span> over budget.
  Times in milliseconds.
</p>
<p class="legend">
  <strong>drift</strong> is the change in p90 since the scenario's history
  began &mdash; the signal a single baseline comparison cannot give you, since
  many individually-passing changes can still add up to a much slower screen.
</p>
</body>
</html>
''';
}
