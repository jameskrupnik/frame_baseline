# frame_baseline example

A runnable, end-to-end demonstration: two scrollable screens, measured with real
engine frame timings, gated against committed baselines.

- **Smooth** — cheap rows, comfortably inside the frame budget.
- **Janky** — each row burns CPU during `build`, so the UI thread overruns the
  budget and drops frames.

The contrast is the point. A perf tool that only ever sees healthy screens
proves nothing; this example produces one `good` screen and one `poor` one from
genuine `FrameTiming`s.

## Setup

Platform scaffolding is generated rather than committed:

```bash
cd example
flutter create --platforms=ios,android,macos .
flutter pub get
```

## Capture and compare

Measurement must run in **profile** mode on **real hardware**. `flutter test`
cannot do this — it has no `--profile`, and under the widget-test binding the
engine reports no frame timings at all. Use `flutter drive`:

```bash
# 1. Capture (repeat -d with your device id: `flutter devices`)
flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/perf_test.dart \
    --profile -d macos | tee perf_run.log

# 2. Compare against the committed baselines
dart run frame_baseline:compare perf_run.log --baseline-dir=perf/baselines

# 3. Re-record intentionally, exactly like golden images
dart run frame_baseline:compare perf_run.log --baseline-dir=perf/baselines --update
```

Step 2 exits non-zero on regression, so it drops straight into CI.

Add `--history` to also record the run and track cumulative drift:

```bash
dart run frame_baseline:compare perf_run.log \
    --baseline-dir=perf/baselines \
    --history=perf/history.jsonl \
    --label=$(git rev-parse --short HEAD)
```

`perf/history.jsonl` here holds real recorded runs from this demo.

## What a run looks like

Recorded on an Apple Silicon Mac in profile mode:

```
PERF SUMMARY (2 screens)
  smooth_list_scroll  good  ok           build.p90=2.8ms   raster.p90=1.2ms  jank=0.0%
  janky_list_scroll   poor  ok           build.p90=22.9ms  raster.p90=0.8ms  jank=12.6%
```

`good`/`poor` is absolute performance vs the 60fps budget; `ok`/`REGRESSED` is
the verdict against the committed baseline. The two are independent — the janky
screen is legitimately slow *and* legitimately unchanged.

## Why the test takes three samples per screen

`integration_test/perf_test.dart` captures each scenario `sampleCount = 3` times
and the host collapses them to a per-metric median.

This is not incidental. Measured on this repo, two back-to-back runs of an
**identical** build moved `build.p90` by 27% and `build.p99` by 24% — past the
default tolerance bands, so a single-sample gate reported a regression on code
that had not changed. Median-of-3 makes the same comparison pass while still
failing a real regression.

Note also which metric stayed stable across those noisy runs:
`missedBuildBudgetCount` was identical (15 and 15). Missed-frame counts are a
far steadier signal than percentile times — prefer them when tuning a gate for
a noisy environment.
