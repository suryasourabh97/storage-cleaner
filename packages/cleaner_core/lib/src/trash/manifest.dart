import 'dart:convert';

import '../model/path_key.dart';
import '../platform/platform_fs.dart';

const trashFolderName = 'StorageCleaner Trash';
const manifestFileName = 'manifest.json';
const readmeFileName = 'README.txt';

const readmeText = '''
StorageCleaner Trash
====================

This folder holds files that Storage Cleaner moved to its trash.
Nothing in here has been deleted.

Each file keeps its original name and sits in a folder that mirrors where it
came from. For example, a file that was in

    Downloads\\report.pdf

is now in

    StorageCleaner Trash\\Downloads\\report.pdf

To recover a file without the app, open this folder in File Explorer and
move the file back where you want it.

manifest.json lists every file with its original location and the date it
was moved here. If Storage Cleaner is reinstalled, it reads that list and can
restore the files for you.

Storage Cleaner never deletes files from this folder unless you confirm it.
Uninstalling the app does not delete this folder.
''';

final class ManifestItem {
  const ManifestItem({
    required this.trashPath,
    required this.originalPath,
    required this.size,
    required this.trashedAt,
  });

  /// Absolute path in the trash.
  final String trashPath;
  final String originalPath;
  final int size;
  final DateTime trashedAt;
}

/// The durable record of one trash root (ADR-002). Paths are stored
/// relative to the trash root so the manifest stays valid if the drive
/// letter changes.
final class TrashManifest {
  TrashManifest._(this.trashRoot, this._fs, this._items);

  final String trashRoot;
  final PlatformFs _fs;
  final Map<String, ManifestItem> _items;

  static const version = 1;

  String get _file => winPath.join(trashRoot, manifestFileName);

  Iterable<ManifestItem> get items => _items.values;

  /// Loads the manifest, or an empty one if missing or unreadable. A corrupt
  /// manifest is kept aside rather than overwritten.
  static TrashManifest load(PlatformFs fs, String trashRoot) {
    final root = normalizePath(trashRoot);
    final file = winPath.join(root, manifestFileName);
    final items = <String, ManifestItem>{};
    if (fs.stat(file) == null) return TrashManifest._(root, fs, items);
    try {
      final json = jsonDecode(utf8.decode(fs.readBytes(file)));
      final list = (json as Map<String, Object?>)['items'] as List<Object?>;
      for (final raw in list) {
        final m = raw as Map<String, Object?>;
        final trashPath = winPath.join(root, m['trashPath'] as String);
        final originalPath = m['originalPath'] as String;
        final originalRel = m['originalRelative'] as String?;
        items[pathKey(trashPath)] = ManifestItem(
          trashPath: trashPath,
          originalPath: _rebase(originalPath, originalRel, root),
          size: m['size'] as int,
          trashedAt: DateTime.parse(m['trashedAt'] as String).toUtc(),
        );
      }
    } on Object {
      final aside = winPath.join(root, 'manifest.corrupt.json');
      if (fs.stat(aside) == null) fs.replaceFile(file, aside);
    }
    return TrashManifest._(root, fs, items);
  }

  /// If the drive letter changed, point the original path at the new letter
  /// for items that came from the same drive as the trash root.
  static String _rebase(String original, String? originalRel, String root) {
    if (originalRel == null) return original;
    return winPath.join(driveRoot(root), originalRel);
  }

  bool contains(String trashPath) => _items.containsKey(pathKey(trashPath));

  ManifestItem? itemFor(String trashPath) => _items[pathKey(trashPath)];

  void add(ManifestItem item) => _items[pathKey(item.trashPath)] = item;

  void remove(String trashPath) => _items.remove(pathKey(trashPath));

  /// Writes atomically: temp file, then replace.
  void save() {
    _fs.createDirectories(trashRoot);
    final sameDrive = driveRoot(trashRoot);
    final json = {
      'version': version,
      'items': [
        for (final i in _items.values)
          {
            'trashPath': winPath.relative(i.trashPath, from: trashRoot),
            'originalPath': i.originalPath,
            if (samePath(driveRoot(i.originalPath), sameDrive))
              'originalRelative':
                  winPath.relative(i.originalPath, from: sameDrive),
            'size': i.size,
            'trashedAt': i.trashedAt.toUtc().toIso8601String(),
          },
      ],
    };
    final tmp = winPath.join(trashRoot, '$manifestFileName.tmp');
    _fs.writeBytes(
      tmp,
      utf8.encode(const JsonEncoder.withIndent('  ').convert(json)),
    );
    _fs.replaceFile(tmp, _file);
  }

  /// Creates the trash folder with its README if needed.
  static void ensureTrashRoot(PlatformFs fs, String trashRoot) {
    fs.createDirectories(trashRoot);
    final readme = winPath.join(trashRoot, readmeFileName);
    if (fs.stat(readme) == null) {
      fs.writeBytes(readme, utf8.encode(readmeText.replaceAll('\n', '\r\n')));
    }
  }
}
