# frame_baseline

Golden-style **performance / jank** regression testing for Flutter screens.

Capture a frame-timing snapshot of a screen, commit it as a baseline, and fail a
run (locally or in CI) when a change regresses it — the same mental model as
golden image tests, but for frames instead of pixels.

> **Status: experimental (0.1.0).** The comparison layer is solid; the hard part
> — making committed baselines robust across devices — is not fully solved. See
> [Known limitation: device variance](#known-limitation-device-variance) before
> relying on this as a hard CI gate.

## Why this exists

Flutter's built-in `integration_test` + `TimelineSummary` can *measure* frame
times, and golden tooling (`matchesGoldenFile`) diffs *pixels* — but nothing
ties them together into a committed **performance** baseline with tolerances and
a pass/fail gate. `frame_baseline` is a thin layer over Flutter's own
`SchedulerBinding.addTimingsCallback` that does exactly that. No third-party
runtime dependency.

## What it measures

`measureScreenPerformance()` records real engine `FrameTiming`s while you drive a
screen, then produces a `PerfSummary`:

- **build** (UI thread) and **raster** (GPU thread) frame-time stats:
  avg / p50 / p90 / p99 / worst
- **missedBuildBudgetCount** / **missedRasterBudgetCount** — frames slower than
  the 16.67 ms (60 fps) budget. This is the jank signal.

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
```

## Baselines are golden files

Commit one `perf/baselines/<scenario>.perf.json` per scenario, review changes to
them in PRs, and regenerate intentionally with `--update` — exactly like golden
images.

## Tuning tolerances

`PerfComparator` takes a `PerfTolerance` controlling how much regression is
allowed (default: +15 % p90, +20 % p99, +30 % worst, +2 janky frames, plus a
1 ms absolute-slack floor so tiny baselines don't fail on sub-millisecond noise).

```dart
const PerfComparator(
  tolerance: PerfTolerance(maxP90BuildRegressionRatio: 0.10),
);
```

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

## License

[MIT](LICENSE)
