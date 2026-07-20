// dart format off
import 'dart:convert' show jsonDecode, jsonEncode;

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

/// Result of scanning a device/CI log for [reportPerfSummary] lines.
class PerfLogExtraction {
  const PerfLogExtraction({required this.summaries, required this.errors});

  /// Successfully parsed summaries, in log order.
  final List<PerfSummary> summaries;

  /// Human-readable messages for lines that carried [kPerfSummaryMarker] but
  /// failed to parse. Empty when every marked line parsed cleanly.
  final List<String> errors;
}

/// Scans [log] for [kPerfSummaryMarker] lines and parses each into a
/// [PerfSummary].
///
/// Everything up to and including the marker on a line is ignored (so device
/// log prefixes like timestamps are fine). Lines that carry the marker but fail
/// to parse are collected into [PerfLogExtraction.errors] rather than thrown, so
/// one corrupt line doesn't abort the whole run.
PerfLogExtraction extractPerfSummaries(String log) {
  final summaries = <PerfSummary>[];
  final errors = <String>[];
  for (final line in log.split('\n')) {
    final idx = line.indexOf(kPerfSummaryMarker);
    if (idx == -1) continue;
    final jsonStr = line.substring(idx + kPerfSummaryMarker.length).trim();
    try {
      summaries.add(
        PerfSummary.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>),
      );
    } catch (e) {
      errors.add('Skipping unparsable perf line: $e');
    }
  }
  return PerfLogExtraction(summaries: summaries, errors: errors);
}
