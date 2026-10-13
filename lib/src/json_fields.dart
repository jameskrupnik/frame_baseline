// dart format off
import 'dart:convert' show jsonDecode;
// dart format on

// Strict readers for the JSON this package writes. Baselines and history are
// files people hand-edit and merge, so a wrong shape must surface as a
// [FormatException] naming the field — something callers can catch and report
// — rather than a [TypeError] from an `as` cast.

/// Decodes [source], which must hold a single JSON object.
///
/// Throws a [FormatException] if [source] is not valid JSON or is not an
/// object.
Map<String, dynamic> decodeJsonObject(String source) {
  final decoded = jsonDecode(source);
  if (decoded is Map<String, dynamic>) return decoded;
  throw FormatException(
    'expected a JSON object, got ${decoded.runtimeType}',
    source,
  );
}

/// Reads [key] from [json] as a [T], or throws a [FormatException].
///
/// A nullable [T] accepts a missing key.
T readField<T>(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is T) return value;
  throw FormatException(
    'expected "$key" to be $T, got ${value.runtimeType}',
  );
}

/// Reads a finite JSON number at [key] as a [double], or throws a
/// [FormatException].
///
/// `jsonDecode` reads an out-of-range literal such as `1e400` as infinity; an
/// infinite baseline would set an infinite limit that every run passes.
double readDouble(Map<String, dynamic> json, String key) {
  final value = readField<num>(json, key).toDouble();
  if (value.isFinite) return value;
  throw FormatException('expected "$key" to be a finite number, got $value');
}

/// The version of the baseline and history JSON this package writes.
///
/// Every baseline and history line carries it as `schemaVersion`, so a later
/// release that changes the shape can tell old files from new ones instead of
/// misreading them.
const int kSchemaVersion = 1;

/// Throws a [FormatException] unless [json] is in a schema version this
/// package can read.
///
/// A missing `schemaVersion` reads as 1: files written before the field
/// existed have the version-1 shape.
void checkSchemaVersion(Map<String, dynamic> json) {
  final version = readField<int?>(json, 'schemaVersion') ?? 1;
  if (version == kSchemaVersion) return;
  throw FormatException(
    'unsupported schemaVersion $version; this version of frame_baseline '
    'reads $kSchemaVersion',
  );
}
