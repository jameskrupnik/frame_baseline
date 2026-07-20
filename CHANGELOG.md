# Changelog

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
