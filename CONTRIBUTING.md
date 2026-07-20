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

The pure comparison layer is solid. The hard, unsolved problem is **device
variance** — committed frame-timing baselines are only meaningful on consistent
hardware under consistent load. Contributions that make baselines robust are the
priority:

- Guidance/tooling for pinning a device profile (e.g. a single Firebase Test Lab
  model) and deriving tolerances from observed run-to-run noise.
- Multiple-sample capture and statistical comparison (median-of-N, confidence
  intervals) instead of a single run vs. a single baseline.
- A worked end-to-end example wired to a device farm in CI.

Recently landed (no longer roadmap items): raster-thread gating, ratio-based
janky-frame comparison, and the cross-screen HTML/terminal report.

## Guidelines

- Keep the core (`lib/src/*` except `measure_screen_performance.dart`) pure Dart
  so the CLI can run under the standalone VM.
- Add tests for new comparison logic.
- Discuss larger changes in an issue first.
