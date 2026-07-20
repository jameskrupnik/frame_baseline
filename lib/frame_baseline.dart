/// Golden-style performance / jank regression testing for Flutter screens.
///
/// Drive a screen inside `measureScreenPerformance` to capture a `PerfSummary`,
/// emit it with `reportPerfSummary`, then compare against a committed baseline
/// with `PerfComparator` (see the `frame_baseline_compare` CLI in `bin/`).
library;

export 'src/frame_stats.dart' show FrameStats;
export 'src/measure_screen_performance.dart'
    show kDefaultFrameBudgetMillis, measureScreenPerformance;
export 'src/perf_comparator.dart'
    show PerfCheck, PerfComparator, PerfComparison;
export 'src/perf_report.dart'
    show
        PerfGrade,
        RegressionStatus,
        ScenarioReport,
        gradeSummary,
        regressionStatusFor,
        renderHtmlReport,
        renderTerminalSummary;
export 'src/perf_reporter.dart'
    show
        PerfLogExtraction,
        extractPerfSummaries,
        kPerfSummaryMarker,
        reportPerfSummary;
export 'src/perf_summary.dart' show PerfSummary;
export 'src/perf_tolerance.dart' show PerfTolerance;
