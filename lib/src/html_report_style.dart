part of 'perf_report.dart';

// The fixed parts of the HTML report, hoisted out of [renderHtmlReport] so
// the function reads as the page's structure.

/// The report's stylesheet: one color pair per grade, shared by cells,
/// badges and the legend.
const _htmlStyle = '''
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
</style>''';

/// The report table's opening tag and header row.
const _htmlTableHead = '''
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
''';

/// What the cell colors and the drift column mean.
const _htmlLegend = '''
<p class="legend">
  Cell color = absolute performance vs each screen's frame budget (one
  refresh interval of the display it was measured on):
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
''';
