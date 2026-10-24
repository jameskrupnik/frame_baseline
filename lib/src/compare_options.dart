part of 'compare_command.dart';

/// The parsed command line of one `frame_baseline:compare` run.
class _CompareOptions {
  const _CompareOptions({
    required this.logPath,
    required this.baselineDir,
    required this.update,
    required this.allowMissing,
    required this.failOnDrift,
    required this.allowDebugBaseline,
    this.reportPath,
    this.historyPath,
    this.label,
    this.gradeLimit,
  });

  /// Reads options from [args], which [_usageError] has already accepted.
  factory _CompareOptions.fromArgs(List<String> args) {
    final grade = _optionValue(args, '--fail-on-grade');
    return _CompareOptions(
      logPath: args.firstWhere((a) => !a.startsWith('-')),
      baselineDir: _optionValue(args, '--baseline-dir') ?? 'perf/baselines',
      update: args.contains('--update'),
      allowMissing: args.contains('--allow-missing'),
      failOnDrift: args.contains('--fail-on-drift'),
      allowDebugBaseline: args.contains('--allow-debug-baseline'),
      reportPath: _optionValue(args, '--report'),
      historyPath: _optionValue(args, '--history'),
      label: _optionValue(args, '--label'),
      gradeLimit: grade == null ? null : PerfGrade.tryParse(grade),
    );
  }

  final String logPath;
  final String baselineDir;

  /// Rewrite baselines from the log instead of comparing against them.
  final bool update;

  /// Compare only the scenarios in the log, instead of failing for every
  /// baseline the log has no summary for.
  final bool allowMissing;
  final bool failOnDrift;

  /// Let --update record a capture measured in debug mode.
  final bool allowDebugBaseline;
  final String? reportPath;
  final String? historyPath;

  /// Tag for this run's history entries, typically the commit SHA.
  final String? label;

  /// Fail any scenario graded this or worse; null leaves grades advisory.
  final PerfGrade? gradeLimit;
}
