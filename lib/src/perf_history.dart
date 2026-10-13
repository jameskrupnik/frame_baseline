// dart format off
import 'dart:convert' show jsonEncode;

import 'package:frame_baseline/src/json_fields.dart'
    show decodeJsonObject, readField;

import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;

part 'perf_history_entry.dart';
// dart format on

/// Result of reading a history log: the entries that parsed, plus messages for
/// any lines that did not.
class PerfHistory {
  /// Creates a history from already-parsed [entries] and [errors].
  ///
  /// Use [parseHistory] to read one from a JSONL file.
  const PerfHistory({required this.entries, required this.errors});

  /// Successfully parsed entries, in file order (oldest first).
  final List<PerfHistoryEntry> entries;

  /// Human-readable messages for unparsable lines.
  final List<String> errors;

  /// Returns the entries for [scenario], oldest first.
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
      entries.add(PerfHistoryEntry.fromJson(decodeJsonObject(line)));
    } on FormatException catch (e) {
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
