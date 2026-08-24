// dart format off
import 'dart:convert' show jsonDecode, jsonEncode;

import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
// dart format on

/// One recorded run of one scenario, as stored in the history log.
///
/// History is append-only JSONL — one JSON object per line — so recording a run
/// never rewrites earlier data and git diffs stay to the appended tail rather
/// than churning the whole file.
class PerfHistoryEntry {
  const PerfHistoryEntry({
    required this.recordedAt,
    required this.summary,
    this.label,
  });

  /// Parses an entry from its [toJson] representation.
  factory PerfHistoryEntry.fromJson(Map<String, dynamic> json) =>
      PerfHistoryEntry(
        recordedAt: DateTime.parse(json['recordedAt'] as String),
        summary: PerfSummary.fromJson(json['summary'] as Map<String, dynamic>),
        label: json['label'] as String?,
      );

  /// When the run was recorded.
  final DateTime recordedAt;

  /// The run's measurements.
  final PerfSummary summary;

  /// Optional caller-supplied tag — typically the commit SHA, so a drift can be
  /// traced back to the change that introduced it.
  final String? label;

  /// Convenience: the scenario this entry measures.
  String get scenario => summary.scenario;

  Map<String, dynamic> toJson() => {
        'recordedAt': recordedAt.toIso8601String(),
        if (label != null) 'label': label,
        'summary': summary.toJson(),
      };
}

/// Result of reading a history log: the entries that parsed, plus messages for
/// any lines that did not.
class PerfHistory {
  const PerfHistory({required this.entries, required this.errors});

  /// Successfully parsed entries, in file order (oldest first).
  final List<PerfHistoryEntry> entries;

  /// Human-readable messages for unparsable lines.
  final List<String> errors;

  /// Entries for [scenario], oldest first.
  List<PerfHistoryEntry> forScenario(String scenario) =>
      entries.where((e) => e.scenario == scenario).toList(growable: false);

  /// Every scenario present in the history, in first-seen order.
  List<String> get scenarios {
    final seen = <String>[];
    for (final e in entries) {
      if (!seen.contains(e.scenario)) seen.add(e.scenario);
    }
    return seen;
  }
}

/// Parses append-only JSONL [contents] into a [PerfHistory].
///
/// Blank lines are skipped and unparsable lines are collected rather than
/// thrown, so one corrupt line — a truncated write, a bad merge — doesn't make
/// the whole history unreadable.
PerfHistory parseHistory(String contents) {
  final entries = <PerfHistoryEntry>[];
  final errors = <String>[];
  var lineNumber = 0;

  for (final rawLine in contents.split('\n')) {
    lineNumber++;
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    try {
      entries.add(
        PerfHistoryEntry.fromJson(jsonDecode(line) as Map<String, dynamic>),
      );
    } catch (e) {
      errors.add('Skipping unparsable history line $lineNumber: $e');
    }
  }

  return PerfHistory(entries: entries, errors: errors);
}

/// Encodes [entries] as JSONL lines ready to append to a history file.
///
/// Each line is terminated, so appending to a file that already ends in a
/// newline stays well-formed.
String encodeHistoryEntries(List<PerfHistoryEntry> entries) =>
    entries.map((e) => '${jsonEncode(e.toJson())}\n').join();
