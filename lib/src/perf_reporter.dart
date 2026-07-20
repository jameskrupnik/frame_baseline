// dart format off
import 'dart:convert' show jsonEncode;

import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// Marker prefix the host comparator greps for in test / CI device logs to
/// extract the on-device [PerfSummary] JSON.
const String kPerfSummaryMarker = 'PERF_SUMMARY_JSON::';

/// Emits [summary] as a single machine-parsable log line. Kept as a plain
/// `print` so it survives to stdout on both local runs and device farms.
void reportPerfSummary(PerfSummary summary) {
  // ignore: avoid_print
  print('$kPerfSummaryMarker${jsonEncode(summary.toJson())}');
}
