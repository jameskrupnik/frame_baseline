# frame_baseline

Golden-style **performance / jank** regression testing for Flutter screens.

Capture a frame-timing snapshot of a screen, commit it as a baseline, and fail a
run (locally or in CI) when a change regresses it — the same mental model as
golden image tests, but for frames instead of pixels.

> **Status: experimental (0.1.0).** The comparison layer is solid; the hard part
> — making committed baselines robust across devices — is not fully solved. See
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
- [Baselines are golden files](#baselines-are-golden-files)
- [Tuning tolerances](#tuning-tolerances)
- [CLI reference](#cli-reference)
- [Public API](#public-api)
- [Must run in PROFILE mode on a real device](#must-run-in-profile-mode-on-a-real-device)
- [Known limitation: device variance](#known-limitation-device-variance)
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

**1. Measure inside an integration test** (run in profile mode on a device):

```dart
import 'package:frame_baseline/frame_baseline.dart';

testWidgets('home scroll performance', (tester) async {
  await tester.pumpWidget(const MyApp());
  // ...navigate to the screen under test...

  final summary = await measureScreenPerformance(
    scenario: 'home_scroll',
    action: () async {
      await tester.fling(find.byType(Scrollable).first, const Offset(0, -400), 3000);
      await tester.pumpAndSettle();
    },
  );
  reportPerfSummary(summary); // prints "PERF_SUMMARY_JSON:: {...}" to the log
});
```

**2. Compare against committed baselines on the host:**

```bash
# Capture the device log, then:
dart run frame_baseline:compare device.log --baseline-dir=perf/baselines

# Create/refresh baselines (the "before"):
dart run frame_baseline:compare device.log --baseline-dir=perf/baselines --update
```

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

Exit codes: `0` all screens pass · `1` a regression, missing baseline, or no
summaries found · `64`/`66` usage / file-not-found errors.

## Public API

Import the barrel: `import 'package:frame_baseline/frame_baseline.dart';`

| Symbol                       | Role                                                        |
| ---------------------------- | ---------------------------------------------------------- |
| `measureScreenPerformance()` | Drive a screen, capture engine frame timings.              |
| `reportPerfSummary()`        | Emit a `PerfSummary` as a machine-parsable log line.       |
| `PerfSummary` / `FrameStats` | Pure-Dart snapshot model with JSON round-trip.             |
| `PerfComparator` / `PerfTolerance` | Baseline-vs-current comparison with tolerance bands. |
| `gradeSummary()` / `PerfGrade` | Absolute performance grade for a screen.                |
| `regressionStatusFor()` / `RegressionStatus` | Regression verdict vs a baseline.         |
| `renderTerminalSummary()` / `renderHtmlReport()` | Cross-screen report rendering.        |

## Must run in PROFILE mode on a real device

Debug-mode and simulator/emulator frame times are dominated by asserts/JIT and
are **not** representative. Always measure with `flutter ... --profile` on real
hardware.

## Known limitation: device variance

Committed perf baselines are only meaningful on **consistent hardware under
consistent load**. Run them on a different CI runner or a busy machine and the
numbers drift, so a committed golden is either flaky or so loose it catches
nothing. Mitigations:

- Pin one device (e.g. a single Firebase Test Lab model) for both baseline
  capture and comparison.
- Set `PerfTolerance` from *observed* run-to-run noise, not guesses.
- Prefer gating on **missed-frame counts** and **worst-frame** outliers, which
  are more stable than mean times.

Solving this well is the main goal of the project — see
[CONTRIBUTING.md](CONTRIBUTING.md).

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
