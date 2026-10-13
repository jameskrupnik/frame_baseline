import 'dart:io' show exitCode;

import 'package:frame_baseline/src/compare_command.dart' show runCompare;

/// Host-side gate: compares the perf summaries in a device log against the
/// committed baselines and exits non-zero when the gate fails.
///
/// ```sh
/// dart run frame_baseline:compare <log> \
///     [--baseline-dir=DIR] [--update] [--allow-missing] [--report=FILE.html] \
///     [--history=FILE.jsonl] [--label=SHA] [--fail-on-drift] \
///     [--fail-on-grade=poor]
/// ```
///
/// See `runCompare` for the behavior and the README for every exit code.
void main(List<String> args) => exitCode = runCompare(args);
