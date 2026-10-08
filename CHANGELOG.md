# Changelog

## 0.4.0

- **`ADOPTION.md`** — a practical guide to running this in a real repo: the
  three gates and what each catches, setup, the local routine, copy-paste CI
  workflows, a decision table for when the gate goes red, and how to tune
  tolerances from observed noise rather than guesses.
- **`--fail-on-grade=good|ok|poor`** gates on *absolute* performance, so CI can
  fail any screen whose p90 exceeds the frame budget. Unlike the baseline
  comparison this needs no golden and is portable across devices, and it closes
  a real blind spot: a screen baselined while already slow passes its baseline
  comparison indefinitely. `PerfGrade.severity` orders grades and
  `PerfGrade.tryParse()` reads a threshold name.
- **The CLI rejects arguments it does not understand** (exit `64`): an unknown
  or misspelt option, a value written after a space (`--fail-on-grade poor`),
  a value on an on/off flag, or a second log file. Each of these was previously
  ignored, which silently switched a gate off. `--help` prints usage.
- A corrupt baseline file now fails the gate with its path instead of crashing
  with a stack trace.
- A scenario name containing a path separator or `..` is refused (exit `1`)
  instead of being used as a file name, which under `--update` could write
  outside `--baseline-dir`.
- **Breaking:** `renderHtmlReport` takes `DateTime? generatedAt` instead of
  `String? generatedAtIso`.
- `PerfSummary.fromJson`, `FrameStats.fromJson` and `PerfHistoryEntry.fromJson`
  throw a `FormatException` naming the bad field, instead of a `TypeError`, on
  JSON of the wrong shape. `extractPerfSummaries` and `parseHistory` now collect
  such lines as errors rather than letting them abort the run.
- `example/tool/perf.sh` — the reference capture-and-compare script from the
  guide, kept in the repo so it's exercised rather than aspirational.
- **The frame budget follows the display.** `measureScreenPerformance` used a
  fixed 60 Hz budget (16.67ms), so on a 120 Hz phone a frame could take twice
  its real budget and still not count as missed, and grades were too generous.
  `frameBudgetMillis` is now optional and defaults to one refresh interval of
  the display (8.33ms at 120 Hz), falling back to 60 Hz when the display
  reports no rate; pass it to keep one fixed budget. It now throws
  `ArgumentError` if it is not a positive, finite number. Baselines recorded
  on a high-refresh device before this change were judged at 60 Hz: re-record
  them, or pass `frameBudgetMillis: kDefaultFrameBudgetMillis`. Requires
  Flutter 3.13 (for `FlutterView.display`).
- **`near-limit` no longer fires on unchanged runs.** Nearness was measured as
  90% of the limit itself, so any metric whose tolerance was under ~11% —
  including the missed-frame count of any janky screen — read `near-limit`
  against a baseline recorded from the same capture. It is now 90% of the
  headroom between baseline and limit; a run no worse than its baseline is
  never near its limit.
- Frames the engine finished before the measured action began are no longer
  counted. Outside release mode the engine delivers timings in ~100ms
  batches, so a sample's first batch could include the previous sample's
  frames (for example its scroll-back).
- `PerfSummary.medianOf` throws `ArgumentError` for samples at different frame
  budgets instead of inventing a budget between them, and leaves out empty
  captures, which with an even sample count halved every metric. The CLI
  refuses such a scenario (exit `1`) and carries on with the others.
- Drift is measured only against history recorded at the current run's frame
  budget, so runs from another device's refresh rate no longer skew (or crash)
  the reference.
- The CLI refuses scenario names that differ only by case, which share one
  baseline file on macOS and Windows.
- A history file that does not end in a newline no longer swallows the next
  run's entry. History timestamps and the HTML report's time are written in
  UTC.
- Baseline and history numbers that `jsonDecode` reads as infinity (`1e400`)
  are rejected; an infinite baseline passed every run.
- The HTML report no longer says cells are graded against a 60fps budget.

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

Initial release.

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
