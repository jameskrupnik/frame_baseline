part of 'perf_report.dart';

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
/// [generatedAt], when given, is shown in the header as an ISO-8601
/// timestamp.
String renderHtmlReport(
  List<ScenarioReport> reports, {
  DateTime? generatedAt,
}) {
  final rows = StringBuffer();
  for (final r in reports) {
    rows.writeln(_htmlRow(r));
  }
  final generated = generatedAt == null
      ? ''
      : '<p class="meta">Generated '
          '${_htmlEscape(generatedAt.toIso8601String())}</p>';

  return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>frame_baseline &middot; performance report</title>
$_htmlStyle
</head>
<body>
<h1>frame_baseline &middot; performance report</h1>
$generated
$_htmlTableHead  <tbody>
$rows  </tbody>
</table>
$_htmlLegend</body>
</html>
''';
}

/// One screen's row of the report table.
String _htmlRow(ScenarioReport r) {
  final s = r.summary;
  final budget = s.frameBudgetMillis;
  return '''
      <tr>
        <td class="scenario">${_htmlEscape(s.scenario)}</td>
        <td class="badge ${_gradeClass(r.grade)}">${_gradeLabel(r.grade)}</td>
        <td class="badge ${_statusClass(r.status)}">${_statusLabel(r.status)}</td>
        ${_millisCell(s.build.p90, budget)}
        ${_millisCell(s.build.p99, budget)}
        ${_millisCell(s.build.worst, budget)}
        ${_millisCell(s.raster.p90, budget)}
        ${_millisCell(s.raster.p99, budget)}
        ${_millisCell(s.raster.worst, budget)}
        ${_jankCell(s.jankyBuildFrameRatio)}
        ${_jankCell(s.jankyRasterFrameRatio)}
        <td class="num">${s.sampledFrameCount}</td>
        ${_driftCell(r.drift)}
      </tr>''';
}
