# Contributing

Thanks for your interest in `frame_baseline`! It's early and the roadmap below
is where help is most valuable.

## Getting started

```bash
flutter pub get
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

CI runs those same four steps; please make sure they pass before opening a PR.

## Where help is most needed

The hard, unsolved problem is **device variance** — committed frame-timing
baselines are only meaningful on consistent hardware under consistent load.
Median-of-N sampling takes the edge off (see the measured numbers in the
README), but it does not solve it. Contributions here are the priority:

- **Trend history.** Today a run is compared against one baseline, pass/fail.
  There is no record of previous runs, so slow drift is invisible: ten changes
  at +3% each all pass individually while the screen ends up 35% slower.
  Appending each run to a history file and gating on the trend would close this.
- **Confidence intervals** rather than a median plus fixed tolerance bands —
  derive the band from the observed spread of the samples themselves.
- **Guidance/tooling for pinning a device profile** (e.g. a single Firebase Test
  Lab model) and deriving tolerances from observed run-to-run noise.
- **A worked example wired to a device farm in CI.** `example/` runs locally via
  `flutter drive`; nothing yet runs it on hosted hardware.

Recently landed (no longer roadmap items): raster-thread gating, ratio-based
janky-frame comparison, the cross-screen HTML/terminal report, median-of-N
sampling, hard failure on empty captures, and the end-to-end `example/` app.

## Guidelines

- Keep the core (`lib/src/*` except `measure_screen_performance.dart`) pure Dart
  so the CLI can run under the standalone VM.
- Add tests for new comparison logic.
- Discuss larger changes in an issue first.
