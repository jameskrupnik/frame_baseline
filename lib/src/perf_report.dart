// dart format off
import 'dart:math' as math show max;

import 'package:frame_baseline/src/perf_comparator.dart'
    show PerfCheck, PerfComparison;
import 'package:frame_baseline/src/perf_summary.dart' show PerfSummary;
import 'package:frame_baseline/src/perf_trend.dart' show PerfDrift;

part 'html_report.dart';
part 'html_report_style.dart';
part 'perf_grade.dart';
part 'regression_status.dart';
part 'scenario_report.dart';
part 'terminal_report.dart';
// dart format on

// Grading, regression status and the terminal and HTML renderings of a run,
// one part file each.
