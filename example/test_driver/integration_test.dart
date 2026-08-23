// Driver entrypoint so the perf capture can run in PROFILE mode.
//
// `flutter test integration_test/...` only runs in debug, where frame times are
// dominated by asserts and JIT. `flutter drive` accepts `--profile`, which is
// the only mode whose numbers are worth committing as a baseline:
//
//   flutter drive \
//     --driver=test_driver/integration_test.dart \
//     --target=integration_test/perf_test.dart \
//     --profile -d <device-id>

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
