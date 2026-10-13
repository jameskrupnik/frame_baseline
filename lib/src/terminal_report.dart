part of 'perf_report.dart';

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

/// Renders a cross-screen summary table of [reports] for the terminal.
///
/// Set [colored] to false when stdout is not a TTY (or `NO_COLOR` is set) to
/// get plain text without ANSI escapes. Returns an empty string when [reports]
/// is empty.
String renderTerminalSummary(
  List<ScenarioReport> reports, {
  required bool colored,
}) {
  if (reports.isEmpty) return '';
  final scenarioWidth =
      reports.map((r) => r.summary.scenario.length).fold(8, math.max);

  final title = 'PERF SUMMARY (${reports.length} '
      'screen${reports.length == 1 ? '' : 's'})';
  final buf = StringBuffer()
    ..writeln()
    ..writeln(_paint(title, _ansiBold, colored: colored));
  for (final r in reports) {
    buf.writeln(_terminalRow(r, scenarioWidth, colored: colored));
  }
  _writeDriftSection(buf, reports, colored: colored);
  return buf.toString();
}

/// One screen's line of the terminal summary, its name padded to
/// [scenarioWidth].
String _terminalRow(
  ScenarioReport r,
  int scenarioWidth, {
  required bool colored,
}) {
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
  return '  $name  $grade  $status  '
      'build.p90=${s.build.p90.toStringAsFixed(1)}ms  '
      'raster.p90=${s.raster.p90.toStringAsFixed(1)}ms  '
      'jank=${(jank * 100).toStringAsFixed(1)}%$drift';
}

/// Lists the drifted screens under the table, or writes nothing when none
/// drifted.
void _writeDriftSection(
  StringBuffer buf,
  List<ScenarioReport> reports, {
  required bool colored,
}) {
  final drifted = reports.where((r) => r.drift?.drifted ?? false).toList();
  if (drifted.isEmpty) return;
  buf
    ..writeln()
    ..writeln(_paint('DRIFT since history began', _ansiBold, colored: colored));
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

/// Formats a drift [ratio] as a signed percentage, e.g. `+42%` or `-8%`.
///
/// An infinite ratio (drift from a zero reference) formats as `n/a`.
String formatDriftRatio(double ratio) {
  if (ratio.isInfinite) return 'n/a';
  final pct = ratio * 100;
  final sign = pct >= 0 ? '+' : '';
  return '$sign${pct.toStringAsFixed(0)}%';
}
