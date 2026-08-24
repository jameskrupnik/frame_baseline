# Changelog

## 0.3.0

Adds performance tracking over time. A baseline gate only ever answers "did
*this* change make it worse?", and after each accepted change the baseline moves
with it — so a run of individually-passing changes can leave a screen far slower
than it started with every comparison green. Seven steps of +12% each all pass
the default gate and total +98%.

- `--history=FILE.jsonl` appends each run to an append-only history log and
  reports how far each scenario has drifted since that history began. Appends
  never rewrite earlier lines, so diffs stay to the new tail.
- `--label=SHA` tags a history entry, so a drift can be traced to the commit
  that introduced it. `--fail-on-drift` makes drift fail the build; it is
  advisory by default, since the threshold is a project-specific policy.
- Drift is measured against the median of a scenario's **oldest**
  `kDefaultReferenceWindow` (3) runs. The anchor is deliberately not rolling:
  anchoring to recent runs is what lets creep hide. Truncate the history file to
  re-anchor after an accepted slowdown.
- New public API: `PerfHistory`, `PerfHistoryEntry`, `parseHistory()`,
  `encodeHistoryEntries()`, `PerfDrift`, `analyzeDrift()`,
  `PerfTolerance.drift`, `formatDriftRatio()`.
- Terminal and HTML reports gained a drift column, plus a summary of drifted
  screens. A scenario with no history yet renders as `—`, not as zero drift.
- Runs whose capture was empty are excluded from the history, so a dead run
  can't poison the trend.

## 0.2.0

First release validated end to end against real engine frame timings on real
hardware, via the new `example/` app.

Fixed — silent green on failed measurements:

- A capture that recorded no frames used to produce an all-zeros `PerfSummary`,
  which graded `good` and passed all eight tolerance checks. A misconfigured
  setup therefore reported a permanently healthy screen. Now refused at every
  layer:
  - `measureScreenPerformance` throws `InsufficientFrameDataException` when
    fewer than `minSampledFrames` (default 5) frames were captured, with a
    message naming the likely cause.
  - `PerfComparator` short-circuits to a failure with `PerfComparison.errors`
    when either side captured no frames.
  - `frame_baseline:compare` refuses to record or compare a zero-frame capture
    and exits non-zero.
  - `gradeSummary` returns the new `PerfGrade.unknown` instead of `good`.
- `measureScreenPerformance` warns when run outside profile mode.

Added — median-of-N sampling, for gate stability:

- `PerfSummary.medianOf()` collapses repeated captures of one scenario to their
  per-metric median, and `frame_baseline:compare` applies it automatically to
  scenarios that appear more than once in a log.
- Motivation, measured on an idle machine: two back-to-back runs of an identical
  build moved `build.p90` by 27% and `build.p99` by 24% — past the default
  tolerances, failing the gate on unchanged code. Median-of-3 passes that same
  comparison while still failing all four build checks on an injected
  regression.
- `measureScreenPerformance` gains `settleDuration`, waited after the action so
  the engine can deliver its final batch of timings.

Added — `example/`:

- A demo app with a smooth and a deliberately janky list, an
  `integration_test` that captures three samples of each, committed baselines,
  and a `flutter drive` driver for profile-mode runs.

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
