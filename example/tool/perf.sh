#!/usr/bin/env bash
# Capture frame timings on the pinned device and compare against baselines.
#
#   tool/perf.sh                 # gate against committed baselines
#   tool/perf.sh --update        # accept the current numbers as the new goldens
#   PERF_DEVICE=macos tool/perf.sh
#
# Any extra arguments are forwarded to frame_baseline:compare, so
# `tool/perf.sh --fail-on-drift` works too.
#
# This is the reference copy of the script described in ADOPTION.md. Adjust the
# paths and pin PERF_DEVICE to a single device: frame timings are not comparable
# across hardware.
set -euo pipefail

cd "$(dirname "$0")/.."

DEVICE="${PERF_DEVICE:-macos}"
LOG=perf_run.log

echo "Capturing on device: $DEVICE"
flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/perf_test.dart \
    --profile -d "$DEVICE" | tee "$LOG"

dart run frame_baseline:compare "$LOG" \
    --baseline-dir=perf/baselines \
    --history=perf/history.jsonl \
    --label="$(git rev-parse --short HEAD)" \
    --report=perf/report.html \
    "$@"
