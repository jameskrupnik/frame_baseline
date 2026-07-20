# Changelog

## Unreleased

- Cross-screen overview: `frame_baseline:compare` now prints a color-coded
  summary of all screens (absolute performance grade + regression status), and
  a new `--report=FILE.html` flag writes a shareable HTML report with
  per-metric cell colors. Works in `--update` mode too.
- New public API in `perf_report.dart`: `PerfGrade`, `RegressionStatus`,
  `ScenarioReport`, `gradeSummary()`, `regressionStatusFor()`,
  `renderTerminalSummary()`, `renderHtmlReport()`.
- `PerfComparator` now gates the GPU/raster thread too (`raster.p90/p99/worst`
  and `missedRasterBudgetCount`), not just the UI/build thread. A raster-only
  regression previously passed silently.
- Janky-frame checks now compare the missed-budget *rate* scaled to each run's
  frame count instead of a raw count, so runs that capture more or fewer frames
  than the baseline are judged fairly.
- `PerfTolerance`: added `maxP90/P99/WorstRasterRegressionRatio`; replaced
  `maxAdditionalMissedBuildBudgetFrames` with `maxAdditionalJankyFrameRatio` +
  `jankyFrameSlack` (applies to both threads).
- `PerfSummary`: added `jankyRasterFrameRatio` getter.

## 0.1.0

Initial release. Experimental — API may change.

- `measureScreenPerformance()` — records real engine `FrameTiming`s (build +
  raster) while driving a screen and returns a jank-focused `PerfSummary`.
- `PerfSummary` / `FrameStats` — pure-Dart snapshot model with avg/p50/p90/p99/
  worst frame times and missed-frame-budget counts; JSON round-trip.
- `PerfComparator` / `PerfTolerance` — baseline-vs-current comparison with
  configurable tolerance bands.
- `reportPerfSummary()` — emits a machine-parsable log line.
- `frame_baseline:compare` CLI — extracts summaries from a device/CI log and
  compares against committed golden baselines (or `--update`s them); non-zero
  exit on regression for use as a CI gate.
