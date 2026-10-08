// dart format off
import 'dart:convert' show jsonEncode;

import 'package:frame_baseline/src/json_fields.dart' show decodeJsonObject;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// Marker prefix the host comparator greps for in test / CI device logs to
/// extract the on-device [PerfSummary] JSON.
const String kPerfSummaryMarker = 'PERF_SUMMARY_JSON::';

/// Emits [summary] as a single machine-parsable log line.
///
/// The line is [kPerfSummaryMarker] followed by the summary's JSON, written
/// with a plain `print` so it reaches stdout on both local runs and device
/// farms. Read it back with [extractPerfSummaries].
void reportPerfSummary(PerfSummary summary) {
  // `print`, not `debugPrint`: an app may override or silence debugPrint, and
  // this line must reach the device log for the host to parse it.
  // ignore: avoid_print
  print('$kPerfSummaryMarker${jsonEncode(summary.toJson())}');
}

/// Result of scanning a device/CI log for [reportPerfSummary] lines.
class PerfLogExtraction {
  /// Creates an extraction result from parsed [summaries] and [errors].
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
      summaries.add(PerfSummary.fromJson(decodeJsonObject(jsonStr)));
    } on FormatException catch (e) {
      errors.add('Skipping unparsable perf line: $e');
    }
  }
  return PerfLogExtraction(summaries: summaries, errors: errors);
}
