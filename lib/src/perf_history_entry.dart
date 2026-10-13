part of 'perf_history.dart';

/// One recorded run of one scenario, as stored in the history log.
///
/// History is append-only JSONL — one JSON object per line — so recording a run
/// never rewrites earlier data and git diffs stay to the appended tail rather
/// than churning the whole file.
class PerfHistoryEntry {
  /// Creates an entry for [summary], recorded at [recordedAt].
  const PerfHistoryEntry({
    required this.recordedAt,
    required this.summary,
    this.label,
  });

  /// Parses an entry from its [toJson] representation.
  ///
  /// Throws a [FormatException] if a field is missing or has the wrong type,
  /// or if `schemaVersion` is one this package cannot read.
  factory PerfHistoryEntry.fromJson(Map<String, dynamic> json) {
    checkSchemaVersion(json);
    return PerfHistoryEntry(
      recordedAt: DateTime.parse(readField<String>(json, 'recordedAt')),
      summary: PerfSummary.fromJson(
        readField<Map<String, dynamic>>(json, 'summary'),
      ),
      label: readField<String?>(json, 'label'),
    );
  }

  /// When the run was recorded.
  final DateTime recordedAt;

  /// The run's measurements.
  final PerfSummary summary;

  /// Optional caller-supplied tag — typically the commit SHA, so a drift can be
  /// traced back to the change that introduced it.
  final String? label;

  /// The scenario this entry measures, taken from [summary].
  String get scenario => summary.scenario;

  /// Converts this entry to a JSON-encodable map, the inverse of
  /// [PerfHistoryEntry.fromJson].
  ///
  /// [label] is omitted when null, so untagged lines stay short.
  Map<String, dynamic> toJson() => {
        'schemaVersion': kSchemaVersion,
        'recordedAt': recordedAt.toIso8601String(),
        if (label != null) 'label': label,
        'summary': summary.toJson(),
      };
}
