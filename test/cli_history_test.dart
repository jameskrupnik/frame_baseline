// CLI tests for --history: recording runs and reporting cumulative drift.
// See cli_gate_test.dart for why the CLI is tested as a subprocess.

// dart format off
import 'dart:io' show File, FileMode, ProcessResult;

import 'package:flutter_test/flutter_test.dart';
import 'package:frame_baseline/frame_baseline.dart' show parseHistory;

import 'support/cli_harness.dart';
// dart format on

void main() {
  final cli = CliHarness();
  ProcessResult run(List<String> lines, {List<String> args = const []}) =>
      cli.run(lines, args: args);

  group('history and drift', () {
    /// Records [millis] as one run in the history file, via the CLI.
    void record(String history, double millis, {String? label}) {
      run(
        [
          logLine(cliSummary([millis, millis, millis])),
        ],
        args: [
          '--update',
          '--history=$history',
          if (label != null) '--label=$label',
        ],
      );
    }

    test('appends a line per run and records the label', () {
      final history = '${cli.tmp.path}/history.jsonl';
      record(history, 4, label: 'abc123');
      record(history, 5, label: 'def456');

      final lines = File(history).readAsLinesSync()
        ..removeWhere((l) => l.trim().isEmpty);
      expect(lines, hasLength(2));
      expect(lines.first, contains('abc123'));
      expect(lines.last, contains('def456'));
    });

    test('reports cumulative drift once there is enough history', () {
      final history = '${cli.tmp.path}/history.jsonl';
      for (var i = 0; i < 3; i++) {
        record(history, 4);
      }

      // A run far slower than the recorded origin.
      final result = run(
        [
          logLine(cliSummary(const [12, 12, 12])),
        ],
        args: ['--history=$history'],
      );

      expect(result.stdout, contains('drift='));
      expect(result.stdout, contains('DRIFT since history began'));
    });

    test('does not fail the gate on drift unless asked', () {
      final history = '${cli.tmp.path}/history.jsonl';
      for (var i = 0; i < 3; i++) {
        record(history, 4);
      }
      // Re-baseline so the per-change gate itself is clean.
      run(
        [
          logLine(cliSummary(const [12, 12, 12])),
        ],
        args: [
          '--update',
          '--history=$history',
        ],
      );

      final lenient = run(
        [
          logLine(cliSummary(const [12, 12, 12])),
        ],
        args: ['--history=$history'],
      );
      expect(lenient.exitCode, 0, reason: 'drift is advisory by default');

      final strict = run(
        [
          logLine(cliSummary(const [12, 12, 12])),
        ],
        args: ['--history=$history', '--fail-on-drift'],
      );
      expect(strict.exitCode, 1, reason: '--fail-on-drift must gate on drift');
    });

    test('catches creep that every individual comparison let through', () {
      final history = '${cli.tmp.path}/history.jsonl';

      // Each step is a ~12% regression, inside the per-change tolerance, and
      // re-baselines as it goes — exactly how creep ships unnoticed.
      const steps = <double>[4, 4.5, 5, 5.6, 6.3, 7.1, 7.9];
      for (final step in steps) {
        final result = run(
          [
            logLine(cliSummary([step, step, step])),
          ],
          args: ['--history=$history'],
        );
        // Not the first few runs, which have no baseline yet.
        if (step != steps.first) {
          expect(
            result.stdout,
            isNot(contains('FAIL')),
            reason: 'step $step must pass the per-change gate',
          );
        }
        run(
          [
            logLine(cliSummary([step, step, step])),
          ],
          args: [
            '--update',
            '--baseline-dir=${cli.tmp.path}/baselines',
          ],
        );
      }

      final finalRun = run(
        [
          logLine(cliSummary(const [7.9, 7.9, 7.9])),
        ],
        args: ['--history=$history', '--fail-on-drift'],
      );

      expect(
        finalRun.exitCode,
        1,
        reason: 'the accumulated doubling must be caught',
      );
      expect(finalRun.stdout, contains('DRIFT since history began'));
    });

    test('does not record a run whose capture was empty', () {
      final history = '${cli.tmp.path}/history.jsonl';
      run(
        [logLine(cliSummary(const []))],
        args: ['--update', '--history=$history'],
      );

      expect(
        File(history).existsSync(),
        isFalse,
        reason: 'a dead run would poison the trend',
      );
    });

    test('keeps the run when the history file lacks a final newline', () {
      // A hand edit or a write cut short leaves no newline at the end; the
      // next run's line must not be glued onto it and lost with it.
      final history = '${cli.tmp.path}/history.jsonl';
      record(history, 4);
      final file = File(history);
      file.writeAsStringSync(file.readAsStringSync().trimRight());

      record(history, 5, label: 'next');

      final parsed = parseHistory(file.readAsStringSync());
      expect(parsed.errors, isEmpty);
      expect(parsed.entries, hasLength(2));
      expect(parsed.entries.last.label, 'next');
    });

    test('records timestamps in UTC so machines in other zones agree', () {
      final history = '${cli.tmp.path}/history.jsonl';
      record(history, 4);

      final entry =
          parseHistory(File(history).readAsStringSync()).entries.single;
      expect(entry.recordedAt.isUtc, isTrue);
    });

    test('survives a corrupt history line', () {
      final history = '${cli.tmp.path}/history.jsonl';
      record(history, 4);
      File(history).writeAsStringSync('{ not json\n', mode: FileMode.append);

      final result = run(
        [
          logLine(cliSummary(const [4, 4, 4])),
        ],
        args: ['--history=$history'],
      );

      expect(result.stderr, contains('unparsable history line'));
      expect(result.exitCode, 0);
    });

    test('rejects --fail-on-drift without a history file', () {
      final result = run(
        [
          logLine(cliSummary(const [4, 4, 4])),
        ],
        args: ['--fail-on-drift'],
      );

      expect(result.exitCode, 64);
      expect(result.stderr, contains('requires --history'));
    });
  });

  test('does not record a refused scenario name in the history', () {
    final history = File('${cli.tmp.path}/history.jsonl');

    final result = run(
      [
        logLine(cliSummary(const [4, 5, 6, 7, 8], scenario: '../escaped')),
      ],
      args: ['--update', '--history=${history.path}'],
    );

    expect(result.exitCode, 1);
    expect(
      history.existsSync() ? history.readAsStringSync() : '',
      isNot(contains('escaped')),
    );
  });
}
