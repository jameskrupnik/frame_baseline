# Adopting frame_baseline in your app

A practical guide to wiring frame performance into a repo so it stays fast —
what to set up, what the routine looks like, and what to do when it goes red.

If you just want the API reference, see the [README](README.md). If you want to
see it all working before committing to it, run [`example/`](example/).

## Contents

- [The mental model: three gates](#the-mental-model-three-gates)
- [Setup](#setup)
- [The routine](#the-routine)
- [Wiring CI](#wiring-ci)
- [When it goes red](#when-it-goes-red)
- [Tuning](#tuning)
- [Pitfalls](#pitfalls)

## The mental model: three gates

The three checks answer different questions and fail independently. Adopt them
in this order — each one is stricter about what it assumes.

| Gate | Question | Needs | Portable across devices? |
| ---- | -------- | ----- | ------------------------ |
| **Baseline** | Did *this change* make it worse? | a committed baseline | ✗ no |
| **Drift** | Are we slower than we *used to be*? | run history | ✗ no |
| **Grade** | Is this screen janky *at all*? | nothing | ✓ yes |

The baseline gate is the workhorse, but it has a structural blind spot: after
each accepted change the baseline moves with it, so a run of individually-green
changes still adds up.

```
4.0ms → 4.5 → 5.0 → 5.6 → 6.3 → 7.1 → 7.9ms
  each step +12%: passes ✓        total: +98%
```

Drift catches that by anchoring to where you started. And the grade gate is the
backstop for both: a p90 over the 16.67ms budget is janky on whatever hardware
measured it, no baseline required — which also catches the case where a screen
was *baselined while already slow* and has been quietly "passing" ever since.

## Setup

### 1. Add the dependency

```yaml
# pubspec.yaml
dev_dependencies:
    frame_baseline:
        git: https://github.com/jameskrupnik/frame_baseline.git
    integration_test:
        sdk: flutter
```

### 2. Add a driver

Profile mode is non-negotiable — debug frame times are dominated by asserts and
JIT, and `flutter test` has no `--profile`. That means `flutter drive`:

```dart
// test_driver/integration_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
```

### 3. Write one perf test

Start with a single screen — your busiest list or feed. Breadth can come later;
the habit is what matters.

```dart
// integration_test/perf_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('feed scroll performance', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();
    // ...navigate to the screen under test...

    // Three samples: a single capture is too noisy to gate on. The host
    // collapses repeated lines for one scenario to their median.
    for (var sample = 0; sample < 3; sample++) {
      final summary = await measureScreenPerformance(
        scenario: 'feed_scroll',
        action: () async {
          for (var i = 0; i < 5; i++) {
            await tester.fling(
              find.byType(Scrollable).first,
              const Offset(0, -500),
              4000,
            );
            await tester.pumpAndSettle();
          }
        },
        settleDuration: const Duration(milliseconds: 500),
      );
      reportPerfSummary(summary);

      // Reset, so every sample measures the same work.
      await tester.fling(find.byType(Scrollable).first, const Offset(0, 20000), 20000);
      await tester.pumpAndSettle();
    }
  });
}
```

Rules for a scenario worth gating:

- **Deterministic.** Same work every run. Fixture data, not live network.
- **Reset between samples**, or sample 2 measures a half-scrolled list.
- **Long enough to matter** — aim for 100+ frames. Under `minSampledFrames` the
  capture throws rather than reporting a misleading average of four frames.

### 4. Pin a device

Frame times are not portable. A baseline recorded on your laptop means nothing
on a phone, and vice versa. **Pick one device and record everything on it.**

```bash
flutter devices   # note the id you'll standardise on
```

A physical mid-range phone is the most honest choice — it's closest to what
users feel, and it has the least headroom to hide regressions. Whatever you
pick, write it down in your repo; anyone re-recording on different hardware
invalidates the goldens.

### 5. Record the first baselines

```bash
flutter drive \
    --driver=test_driver/integration_test.dart \
    --target=integration_test/perf_test.dart \
    --profile -d <device-id> | tee perf_run.log

dart run frame_baseline:compare perf_run.log \
    --baseline-dir=perf/baselines \
    --history=perf/history.jsonl \
    --label=$(git rev-parse --short HEAD) \
    --update
```

Before committing, **read the numbers**. A baseline recorded from an already-slow
screen locks in that slowness as "correct" forever. If a screen grades `poor`,
fix it first — that is what the grade gate is for.

### 6. Commit

```bash
git add perf/baselines perf/history.jsonl
```

Both belong in git. Baselines are golden files; history is append-only, so its
diffs are always just the new tail.

Add to `.gitignore`:

```gitignore
perf_run.log
```

## The routine

Drop this in `tool/perf.sh` so the whole flow is one command:

```bash
#!/usr/bin/env bash
# Capture frame timings on the pinned device and compare against baselines.
# Usage: tool/perf.sh [--update]
set -euo pipefail

DEVICE="${PERF_DEVICE:?set PERF_DEVICE to your pinned device id}"
LOG=perf_run.log

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
```

Then:

| When | Command |
| ---- | ------- |
| Touching a perf-sensitive screen | `tool/perf.sh` before opening the PR |
| Regression confirmed and accepted | `tool/perf.sh --update`, explain why in the PR |
| Before a release | `tool/perf.sh` — the release gate |
| Periodically | `tool/perf.sh` to keep history dense enough to show a trend |

History only becomes useful once it has entries, and drift needs at least 3
recorded runs per scenario before it reports anything. Run it regularly even
when nothing changed — those runs are the anchor everything else is measured
against.

## Wiring CI

**The honest constraint:** measurement needs a real device in profile mode, and
GitHub-hosted runners are shared VMs. Their timing noise will exceed your
tolerances and the gate will flap. Measured on an *idle* dedicated machine,
back-to-back runs of identical code still moved p90 by 27%; a contended cloud VM
is worse. Do not run the capture on a hosted runner and expect a trustworthy
red/green.

Three workable options, cheapest first.

### Option A — local gate + CI hygiene check (start here)

Run captures locally via `tool/perf.sh`, and let hosted CI enforce the things
that *don't* need a device: that the goldens are valid, and that nobody quietly
regenerated them.

```yaml
# .github/workflows/perf-hygiene.yaml
name: Perf hygiene

on: pull_request

jobs:
    baselines:
        runs-on: ubuntu-latest
        steps:
            - uses: actions/checkout@v4
              with:
                  fetch-depth: 0
            - uses: subosito/flutter-action@v2
              with:
                  channel: stable

            # Baselines are golden files: changing them is a deliberate act that
            # deserves a reviewer's attention, not a silent diff in a large PR.
            - name: Flag regenerated baselines
              run: |
                  if git diff --name-only origin/${{ github.base_ref }}...HEAD \
                      | grep -q '^perf/baselines/'; then
                    echo "::warning::This PR changes committed perf baselines."
                    echo "Confirm the regression was intentional and explain it in the PR."
                  fi

            # History is append-only. Edits to existing lines mean a bad merge or
            # a rewrite, either of which corrupts the drift anchor.
            - name: Check history is append-only
              run: |
                  git diff --unified=0 origin/${{ github.base_ref }}...HEAD \
                      -- perf/history.jsonl \
                      | grep '^-[^-]' && {
                        echo "::error::perf/history.jsonl lines were modified or deleted."
                        exit 1
                      } || echo "History is append-only."
```

### Option B — self-hosted runner with a pinned device

The only way to get trustworthy per-PR gating. A spare Mac mini with a phone on
a USB cable is enough.

```yaml
# .github/workflows/perf.yaml
name: Perf

on:
    pull_request:
        paths: ['lib/**', 'pubspec.yaml']
    workflow_dispatch:

jobs:
    measure:
        runs-on: [self-hosted, perf-device]
        # Frame timings are meaningless if two runs share the machine.
        concurrency: perf-device
        steps:
            - uses: actions/checkout@v4
            - run: flutter pub get

            - name: Capture
              run: |
                  flutter drive \
                      --driver=test_driver/integration_test.dart \
                      --target=integration_test/perf_test.dart \
                      --profile -d "$PERF_DEVICE" | tee perf_run.log

            - name: Compare
              run: |
                  dart run frame_baseline:compare perf_run.log \
                      --baseline-dir=perf/baselines \
                      --history=perf/history.jsonl \
                      --label=${{ github.sha }} \
                      --report=perf/report.html

            - uses: actions/upload-artifact@v4
              if: always()
              with:
                  name: perf-report
                  path: perf/report.html
```

That config **blocks on a per-change regression and reports drift without
failing** — the recommended starting policy. Drift is advisory because its
threshold is a project-specific judgement, and a build that fails on a heuristic
nobody tuned gets disabled rather than fixed. Once you've watched real numbers
for a few weeks, add `--fail-on-drift`.

Note the `concurrency` key. Two jobs sharing the device produce garbage.

### Option C — device farm

Firebase Test Lab and similar can run `flutter drive` on a pinned model. Same
rule applies: pin **one** model for both recording and comparison, or the
goldens are meaningless.

### The device-free backstop

One gate needs no baseline and survives running anywhere:

```bash
dart run frame_baseline:compare perf_run.log --fail-on-grade=poor
```

This fails if any screen's p90 exceeds the frame budget. It's the best guard
against *drastic* degradation, because it doesn't care what the baseline says —
only whether users would see jank.

Enable it once every measured screen is at or under budget. If a screen is
legitimately over budget today, this fails permanently until you fix it (there's
no per-scenario exclusion yet), so land it after the cleanup rather than before.

## When it goes red

| Symptom | Likely cause | Do this |
| ------- | ------------ | ------- |
| One metric barely over its limit | Device noise | Re-run. If it passes, it was noise — consider more samples or a looser band. |
| Every build metric up together | A real UI-thread regression | Profile the screen. Don't re-baseline. |
| `raster.*` up, `build.*` flat | GPU-side: shaders, overdraw, large images | Check for new blur/opacity/clipping. |
| `missedBuildBudgetCount` jumped | Real jank users will feel | Highest priority — this is the signal that matters most. |
| Everything up on every screen | Environment, not code | Different device? Machine under load? Verify before touching code. |
| `!` capture-validity warning | Frame budget or frame count diverged | The comparison isn't meaningful. Fix the scenario, then re-record. |
| `captured 0 frames` | Measurement never ran | Widget test instead of `integration_test`, or an action that drove no frames. |
| `drift=+80%` but every check green | Accumulated creep | The thing this exists to catch. Budget real work; don't just re-anchor. |

**The one rule:** `--update` is for *accepted* regressions, not for making red
turn green. Every re-baseline should have a sentence in the PR explaining what
got slower and why that's acceptable. A baseline regenerated without that
sentence is how a perf suite quietly becomes decorative.

## Tuning

Defaults are +15% p90, +20% p99, +30% worst, +2pp jank rate — deliberately loose,
because a flaky gate gets switched off.

Tighten from *observed* noise, not guesses:

1. Run `tool/perf.sh` ~10 times without changing code.
2. Look at the spread of `build.p90` across runs in `perf/history.jsonl`.
3. Set your band comfortably above that spread.

If run-to-run spread is wider than the regression you want to catch, the fix is
**more samples**, not a tighter band. Raise `sampleCount` in the test.

Prefer gating on **counts over percentiles**. In measured back-to-back runs of
identical code, p90 moved 27% while `missedBuildBudgetCount` was *identical*.
Missed-frame counts are both the steadier signal and the one closest to what
users actually perceive.

Metrics ranked by how noisy they are, steadiest first:

| Metric | Stability | Gate on it? |
| ------ | --------- | ----------- |
| `missedBuild/RasterBudgetCount` | very stable | ✓ the primary signal |
| `p90` | moderate | ✓ with a sane band |
| `p99` | noisy | ⚠ wide band |
| `worst` | very noisy — a single frame | ⚠ widest band, or ignore |

`worst` is one frame out of hundreds, so any stall anywhere in the run lands on
it. This is sharpest on screens that are *already* heavy: in this repo's own
example, the deliberately-janky screen wobbled `p99` 39→49ms and `worst` 41→67ms
between runs of identical code, while its frame counts stayed steady (18 → 14).
If a screen is legitimately expensive, loosen its tail bands and trust the
counts.

## Pitfalls

- **Debug-mode numbers.** Meaningless. The library warns; don't record them.
- **Simulators and emulators.** Same problem — not representative.
- **Mixed hardware.** The single fastest way to make baselines worthless.
- **Baselining a slow screen.** Locks in the slowness. Check the grade first.
- **Non-deterministic scenarios.** Live network or random data means noise you
  can't tune away.
- **Sharing a runner.** Concurrent jobs on the measuring machine corrupt timings.
- **Re-baselining reflexively.** The failure mode that makes the whole suite
  decorative.
