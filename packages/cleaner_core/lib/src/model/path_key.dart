import 'package:path/path.dart' as p;

/// Windows path helpers. Windows paths are case-insensitive, so every
/// comparison goes through a normalized, lower-cased key.
///
/// All paths handled by `cleaner_core` are absolute Windows-style paths
/// (`C:\Users\me\Downloads\a.pdf`), regardless of the OS the tests run on.
final p.Context winPath = p.windows;

/// Normalizes [path] (separators, `.`/`..`, trailing separators).
String normalizePath(String path) => winPath.normalize(path);

/// Case-insensitive identity key for [path].
String pathKey(String path) => normalizePath(path).toLowerCase();

/// True if [a] and [b] name the same location.
bool samePath(String a, String b) => pathKey(a) == pathKey(b);

/// True if [child] is strictly inside [parent], comparing whole path
/// segments (so `C:\Users\a` does not contain `C:\Users\ab`).
bool isWithin(String parent, String child) =>
    winPath.isWithin(pathKey(parent), pathKey(child));

/// True if [child] equals [parent] or is inside it.
bool isWithinOrEqual(String parent, String child) =>
    samePath(parent, child) || isWithin(parent, child);

/// The drive root of an absolute path, e.g. `C:\`.
String driveRoot(String path) {
  final root = winPath.rootPrefix(normalizePath(path));
  return root.endsWith(r'\') ? root : '$root\\';
}

/// Inserts ` (n)` before the extension: `report.pdf` -> `report (2).pdf`.
String withCollisionSuffix(String path, int n) {
  final dir = winPath.dirname(path);
  final stem = winPath.basenameWithoutExtension(path);
  final ext = winPath.extension(path);
  return winPath.join(dir, '$stem ($n)$ext');
}
