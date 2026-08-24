# frame_baseline

Golden-style **performance / jank** regression testing for Flutter screens.

Capture a frame-timing snapshot of a screen, commit it as a baseline, and fail a
run (locally or in CI) when a change regresses it — the same mental model as
golden image tests, but for frames instead of pixels.

> **Status: experimental (0.3.0).** Validated end to end against real engine
> timings on real hardware — including catching an injected regression — but
> baselines are only comparable on the device that recorded them. Read
> [Known limitation: device variance](#known-limitation-device-variance) before
> relying on this as a hard CI gate.

## Features

- **Real engine frame timings** — build (UI thread) *and* raster (GPU thread),
  via Flutter's own `SchedulerBinding.addTimingsCallback`. No third-party runtime
  dependency.
- **Committed baselines** — one reviewable JSON golden per screen; regenerate
  intentionally, exactly like golden images.
- **Tolerance-aware gate** — configurable per-metric bands so device noise
  doesn't cause false failures; non-zero exit code drops straight into CI.
- **Median-of-N sampling** — capture a scenario several times per run and the
  comparator gates on the median, so one stalled run doesn't fail the build.
- **No silent passes** — a capture that recorded no frames is an error, not a
  screen with flawless zero-millisecond frames.
- **Drift tracking** — an append-only run history catches slow creep, which a
  moving baseline structurally cannot: many green changes still add up.
- **Cross-screen overview** — a color-coded terminal summary and an optional
  shareable HTML report showing which screens are healthy at a glance.
- **Pure-Dart host CLI** — the comparison and reporting layer runs under the
  standalone Dart VM, no Flutter toolchain needed on the host.

## Contents

- [Why this exists](#why-this-exists)
- [How it works](#how-it-works)
- [Install](#install)
- [Quick start](#quick-start)
- [What it measures](#what-it-measures)
- [Cross-screen overview report](#cross-screen-overview-report)
- [Tracking performance over time](#tracking-performance-over-time)
- [Baselines are golden files](#baselines-are-golden-files)
- [Tuning tolerances](#tuning-tolerances)
- [CLI reference](#cli-reference)
- [Public API](#public-api)
- [Must run in PROFILE mode on a real device](#must-run-in-profile-mode-on-a-real-device)
- [Known limitation: device variance](#known-limitation-device-variance)
- [Failed measurements fail loudly](#failed-measurements-fail-loudly)
- [Contributing](#contributing)
- [License](#license)

## Why this exists

Flutter's built-in `integration_test` + `TimelineSummary` can *measure* frame
times, and golden tooling (`matchesGoldenFile`) diffs *pixels* — but nothing
ties them together into a committed **performance** baseline with tolerances and
a pass/fail gate. `frame_baseline` is a thin layer over Flutter's own
`SchedulerBinding.addTimingsCallback` that does exactly that.

## How it works

Measurement runs **on the device** (inside an integration test); comparison runs
**on the host** (against committed goldens). The two are bridged by a single
machine-parsable log line, so no VM-service timeline extraction is needed.

```
 on device (profile mode)                       on host / CI
┌──────────────────────────┐                 ┌───────────────────────────┐
│ measureScreenPerformance │  PERF_SUMMARY_  │ frame_baseline:compare    │
│   → reportPerfSummary ───┼──── JSON:: ────▶│   → compare vs baselines  │
│      (prints to log)     │   (device log)  │   → report + exit code    │
└──────────────────────────┘                 └───────────────────────────┘
```

## Install

```yaml
dev_dependencies:
    frame_baseline:
        git: https://github.com/jameskrupnik/frame_baseline.git
    # once published: frame_baseline: ^0.1.0
```

## Quick start

**1. Measure inside an integration test.** Capture each scenario a few times —
single captures are too noisy to gate on (see
[device variance](#known-limitation-device-variance)); the host takes the median
of repeated lines for the same scenario.

```dart
import 'package:frame_baseline/frame_baseline.dart';

testWidgets('home scroll performance', (tester) async {
  await tester.pumpWidget(const MyApp());
  // ...navigate to the screen under test...

  for (var sample = 0; sample < 3; sample++) {
    final summary = await measureScreenPerformance(
      scenario: 'home_scroll',
      action: () async {
        await tester.fling(find.byType(Scrollable).first, const Offset(0, -400), 3000);
        await tester.pumpAndSettle();
      },
      settleDuration: const Duration(milliseconds: 500),
    );
    reportPerfSummary(summary); // prints "PERF_SUMMARY_JSON:: {...}" to the log
  }
});
```

**2. Run it in profile mode** via `flutter drive` — `flutter test` has no
`--profile`, and the widget-test binding reports no frame timings at all:

```bash
flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/perf_test.dart \
    --profile -d <device-id> | tee perf_run.log
```

**3. Compare against committed baselines on the host:**

```bash
dart run frame_baseline:compare perf_run.log --baseline-dir=perf/baselines

# Create/refresh baselines (the "before"):
dart run frame_baseline:compare perf_run.log --baseline-dir=perf/baselines --update
```

See [`example/`](example/) for all of this wired up and working.

Exit code is non-zero on regression, so it drops straight into CI. Example
output:

```
[FAIL] home_scroll
  ok   build.p90                baseline=7.10 current=7.40 limit=8.16
  FAIL build.worst             baseline=18.90 current=48.00 limit=24.57
  FAIL missedBuildBudgetCount  baseline=1.00 current=14.00 limit=3.00
  ok   raster.p90               baseline=6.20 current=6.50 limit=7.13
  ok   missedRasterBudgetCount  baseline=0.00 current=1.00 limit=2.00
```

Both the UI thread (`build.*`) and the GPU thread (`raster.*`) are gated, so a
regression on either shows up. Missed-budget frames are compared as a *rate*
scaled to each run's frame count — a run that captures more frames than the
baseline isn't penalized for it.

When a baseline and a current run aren't meaningfully comparable — a different
frame budget (e.g. 60 Hz vs 120 Hz capture) or a large frame-count divergence
(the scenario likely changed) — the comparison prints a non-fatal `!` warning
so a green/red verdict is never trusted blindly.

## What it measures

`measureScreenPerformance()` records real engine `FrameTiming`s while you drive a
screen, then produces a `PerfSummary`:

- **build** (UI thread) and **raster** (GPU thread) frame-time stats:
  avg / p50 / p90 / p99 / worst
- **missedBuildBudgetCount** / **missedRasterBudgetCount** — frames slower than
  the 16.67 ms (60 fps) budget. This is the jank signal.

The budget is configurable via `frameBudgetMillis` (e.g. `1000 / 90` for a 90 Hz
device).

## Cross-screen overview report

Every run also prints a color-coded summary of *all* screens at the end, so you
can see at a glance which ones are healthy:

```
PERF SUMMARY (3 screens)
  home_scroll  good  near-limit   build.p90=4.5ms  raster.p90=5.0ms  jank=0.0%
  chat_list    poor  REGRESSED    build.p90=40.0ms raster.p90=8.0ms  jank=20.0%
  settings     poor  ok           build.p90=15.1ms raster.p90=9.0ms  jank=2.0%
```

Two independent signals per screen:

- **Grade** — absolute performance vs the 60fps budget (`good` <50% of budget,
  `ok` 50–100%, `poor` over budget or janky). Baseline-independent, so it works
  even with `--update` before any baselines exist.
- **vs baseline** — regression status (`ok` / `near-limit` / `REGRESSED`).

Add `--report=FILE.html` for a shareable, color-coded HTML table with per-metric
cell colors (build/raster p90/p99/worst and jank rates):

```bash
dart run frame_baseline:compare device.log \
    --baseline-dir=perf/baselines --report=perf/report.html
```

Terminal colors auto-disable when stdout isn't a TTY or `NO_COLOR` is set.

## Tracking performance over time

A baseline gate answers "did *this* change make it worse?" — and that question
alone is not enough to keep a screen fast. After every accepted change the
baseline moves with it, so a run of individually-innocent changes each land well
inside tolerance while the screen ends up far slower than it started:

```
4.0ms → 4.5 → 5.0 → 5.6 → 6.3 → 7.1 → 7.9ms
  each step +12%: green ✓        total: +98%
```

Every one of those six comparisons passes. Pass `--history` and the run is
appended to an append-only JSONL log, and each scenario is also measured against
the median of its **oldest** recorded runs:

```bash
dart run frame_baseline:compare perf_run.log \
    --baseline-dir=perf/baselines \
    --history=perf/history.jsonl \
    --label=$(git rev-parse --short HEAD)
```

```
PERF SUMMARY (2 screens)
  home_scroll  ok  ok  build.p90=7.9ms  raster.p90=1.2ms  jank=0.0%  drift=+98%

DRIFT since history began
  home_scroll is +98% vs the median of its first 3 runs (7 recorded).
  Individually-passing changes have accumulated.
```

Commit `perf/history.jsonl` alongside the baselines. Appends never rewrite
earlier lines, so the diff is always the new tail.

Notes:

- The anchor is the **oldest** window, not a rolling one. Anchoring to recent
  runs is what lets creep hide, since each new run quietly becomes the normal.
- Drift is **advisory by default** — it reports but doesn't fail the build. Add
  `--fail-on-drift` to enforce it. It's off by default because a drift threshold
  is a project-specific policy, and a gate that fails on a heuristic nobody
  tuned gets ignored or disabled.
- When a slowdown is deliberate and accepted, **truncate the history file** to
  re-anchor — the same intentional act as re-recording a baseline.
- Drift needs `kDefaultReferenceWindow` (3) recorded runs before it reports
  anything; below that there's no trend to speak of.
- `--label` is worth wiring to the commit SHA in CI (`${{ github.sha }}`), so a
  drift can be traced to the change that introduced it.

## Baselines are golden files

Commit one `perf/baselines/<scenario>.perf.json` per scenario, review changes to
them in PRs, and regenerate intentionally with `--update` — exactly like golden
images.

## Tuning tolerances

`PerfComparator` takes a `PerfTolerance` controlling how much regression is
allowed. Defaults, applied to both the build and raster threads: +15 % p90,
+20 % p99, +30 % worst; janky frames may rise +2 percentage points over the
baseline rate (with a 2-frame absolute floor); plus a 1 ms absolute-slack floor
so tiny baselines don't fail on sub-millisecond noise.

```dart
const PerfComparator(
  tolerance: PerfTolerance(maxP90BuildRegressionRatio: 0.10),
);
```

## CLI reference

```
dart run frame_baseline:compare <device-log> [options]
```

| Argument / flag        | Description                                                              |
| ---------------------- | ------------------------------------------------------------------------ |
| `<device-log>`         | Path to the captured device/CI log containing `PERF_SUMMARY_JSON::` lines. |
| `--baseline-dir=DIR`   | Directory of committed baselines (default: `perf/baselines`).             |
| `--update`             | Write/refresh baselines from the log instead of comparing.               |
| `--report=FILE.html`   | Also write a color-coded HTML overview of all screens.                   |
| `--history=FILE.jsonl` | Append this run to a history log and report cumulative drift.            |
| `--label=SHA`          | Tag the history entry, so a drift can be traced to a commit.             |
| `--fail-on-drift`      | Also exit non-zero on cumulative drift (requires `--history`).           |

Exit codes: `0` all screens pass · `1` a regression, missing baseline, or no
summaries found · `64`/`66` usage / file-not-found errors.

## Public API

Import the barrel: `import 'package:frame_baseline/frame_baseline.dart';`

| Symbol                       | Role                                                        |
| ---------------------------- | ---------------------------------------------------------- |
| `measureScreenPerformance()` | Drive a screen, capture engine frame timings.              |
| `InsufficientFrameDataException` | Thrown when a capture recorded too few frames.        |
| `reportPerfSummary()`        | Emit a `PerfSummary` as a machine-parsable log line.       |
| `PerfSummary` / `FrameStats` | Pure-Dart snapshot model with JSON round-trip.             |
| `PerfSummary.medianOf()`     | Collapse repeated samples of a scenario to their median.   |
| `PerfComparator` / `PerfTolerance` | Baseline-vs-current comparison with tolerance bands. |
| `gradeSummary()` / `PerfGrade` | Absolute performance grade for a screen.                |
| `regressionStatusFor()` / `RegressionStatus` | Regression verdict vs a baseline.         |
| `PerfHistory` / `PerfHistoryEntry` | Append-only record of past runs (JSONL).             |
| `parseHistory()` / `encodeHistoryEntries()` | Read and write that record.                 |
| `analyzeDrift()` / `PerfDrift` | Cumulative drift since a scenario's history began.     |
| `renderTerminalSummary()` / `renderHtmlReport()` | Cross-screen report rendering.        |

## Must run in PROFILE mode on a real device

Debug-mode and simulator/emulator frame times are dominated by asserts/JIT and
are **not** representative. Always measure with `flutter ... --profile` on real
hardware.

## Known limitation: device variance

Committed perf baselines are only meaningful on **consistent hardware under
consistent load**. This is the central difficulty of the whole idea, and it is
worth being concrete about how big the effect is.

Measured with [`example/`](example/) on an idle Apple Silicon Mac in profile
mode — two back-to-back runs of an **identical** build, single capture each:

| metric      | run 1   | run 2   | drift | default limit |
| ----------- | ------- | ------- | ----- | ------------- |
| `build.p90` | 18.95ms | 24.16ms | +27%  | +15% → **FAIL** |
| `build.p99` | 4.22ms  | 5.24ms  | +24%  | +20% → **FAIL** |
| `missedBuildBudgetCount` | 15 | 15 | 0% | pass |

Nothing changed but the clock, and the gate went red on both screens. Two
lessons are baked into the tooling as a result:

**Take several samples.** Emit a scenario more than once per run and the
comparator collapses them to a per-metric median, which discards one-off stalls
(a background process, a shader compile) while preserving a regression that
moves every sample. With median-of-3 the same identical-code comparison passes
cleanly, and an injected regression still fails all four build checks.

**Trust counts over percentiles.** Note the last row: missed-frame counts were
*identical* across the two noisy runs. Percentile times are the noisy signal;
janky-frame counts are the steady one. Weight your gate accordingly.

Remaining mitigations, still on the user:

- Pin one device (e.g. a single Firebase Test Lab model) for both baseline
  capture and comparison. Numbers are not portable across hardware.
- Set `PerfTolerance` from *observed* run-to-run noise on your device, not
  guesses.

See [CONTRIBUTING.md](CONTRIBUTING.md) for where this still needs work.

## Failed measurements fail loudly

A capture that recorded no frames has zero for every metric, which satisfies
every tolerance band — so a measurement that never ran would otherwise report a
permanently healthy screen. Each layer refuses it instead:

- `measureScreenPerformance` throws `InsufficientFrameDataException` below
  `minSampledFrames` (default 5), with a message naming the likely cause.
- The CLI refuses to record or compare a zero-frame capture, and exits non-zero.
- `gradeSummary` returns `PerfGrade.unknown`, never `good`.

It also warns when measuring outside profile mode, since those numbers should
never become a baseline.

## Contributing

Issues and PRs welcome. Run the same four checks CI does before opening a PR:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the roadmap and where help is most
valuable.

## License

[MIT](LICENSE)
