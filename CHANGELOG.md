# Changelog

## 0.1.0

Initial release. Experimental — API may change.

Measurement & model:

- `measureScreenPerformance()` — records real engine `FrameTiming`s (build +
  raster) while driving a screen and returns a jank-focused `PerfSummary`.
- `PerfSummary` / `FrameStats` — pure-Dart snapshot model with avg/p50/p90/p99/
  worst frame times and missed-frame-budget counts (`jankyBuildFrameRatio` /
  `jankyRasterFrameRatio`); JSON round-trip.
- `reportPerfSummary()` — emits a machine-parsable log line; `extractPerfSummaries()`
  parses those lines back out of a device/CI log.

Comparison:

- `PerfComparator` / `PerfTolerance` — baseline-vs-current comparison with
  configurable tolerance bands, gating **both** the UI/build thread
  (`build.p90/p99/worst`) and the GPU/raster thread (`raster.p90/p99/worst`),
  plus missed-budget frames on each.
- Janky-frame checks compare the missed-budget *rate* scaled to each run's frame
  count, so runs that capture more or fewer frames than the baseline are judged
  fairly (`maxAdditionalJankyFrameRatio` + `jankyFrameSlack`).
- Comparisons surface `warnings` for incomparable captures — a differing frame
  budget or a large frame-count divergence between baseline and current.

Reporting:

- Cross-screen overview: `frame_baseline:compare` prints a color-coded terminal
  summary of all screens (absolute performance grade + regression status), and
  `--report=FILE.html` writes a shareable HTML report with per-metric cell
  colors. Works in `--update` mode too.
- Public rendering API in `perf_report.dart`: `PerfGrade`, `RegressionStatus`,
  `ScenarioReport`, `gradeSummary()`, `regressionStatusFor()`,
  `renderTerminalSummary()`, `renderHtmlReport()`.

CLI:

- `frame_baseline:compare` — extracts summaries from a device/CI log and
  compares against committed golden baselines (or `--update`s them); non-zero
  exit on regression for use as a CI gate.
