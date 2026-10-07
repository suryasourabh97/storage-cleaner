import 'dart:typed_data';

import 'package:cleaner_core/cleaner_core.dart';

/// Test clock that only moves when told to.
final class FakeClock implements Clock {
  FakeClock([DateTime? start])
      : _now = start ?? DateTime.utc(2026, 10, 7, 12);
  DateTime _now;

  @override
  DateTime now() => _now;

  void advance(Duration d) => _now = _now.add(d);
  void set(DateTime t) => _now = t.toUtc();
}

final class _Node {
  _Node({
    required this.path,
    required this.isDir,
    required this.modified,
    required this.attrs,
    required this.fileId,
    this.data,
    this.size = 0,
  });

  String path;
  final bool isDir;
  DateTime modified;
  FileAttrs attrs;
  final int fileId;

  /// Real contents, or null for size-only test files (avoids allocating
  /// gigabytes for "large file" tests).
  Uint8List? data;
  int size;
  final Set<String> children = <String>{};
}

/// In-memory Windows-like file system: drive volumes, case-insensitive paths,
/// attributes, links, locks, access denial and hard links.
final class MemoryPlatformFs implements PlatformFs {
  MemoryPlatformFs({required this.clock});

  final FakeClock clock;
  final Map<String, _Node> _nodes = {};
  final Map<String, int> _volumes = {};
  final Set<String> _locked = {};
  final Set<String> _denied = {};
  int _nextFileId = 1;

  /// Every mutation call, for assertions.
  final List<String> mutationLog = [];

  // ---------------------------------------------------------------- setup

  void addVolume(String root, int serial) {
    final key = pathKey(driveRoot(root));
    _volumes[key] = serial;
    _nodes.putIfAbsent(
      key,
      () => _Node(
        path: driveRoot(root),
        isDir: true,
        modified: clock.now(),
        attrs: FileAttrs.none,
        fileId: _nextFileId++,
      ),
    );
  }

  void unmountVolume(String root) => _volumes.remove(pathKey(driveRoot(root)));
  void remountVolume(String root, int serial) =>
      _volumes[pathKey(driveRoot(root))] = serial;

  void addDir(String path, {DateTime? modified, FileAttrs? attrs}) {
    _ensureParents(path);
    final key = pathKey(path);
    final existing = _nodes[key];
    if (existing != null) {
      if (attrs != null) existing.attrs = attrs;
      return;
    }
    _nodes[key] = _Node(
      path: normalizePath(path),
      isDir: true,
      modified: modified ?? clock.now(),
      attrs: attrs ?? FileAttrs.none,
      fileId: _nextFileId++,
    );
    _linkToParent(key);
  }

  void addFile(
    String path, {
    int? size,
    List<int>? bytes,
    DateTime? modified,
    FileAttrs attrs = FileAttrs.none,
  }) {
    _ensureParents(path);
    final key = pathKey(path);
    final data = bytes == null ? null : Uint8List.fromList(bytes);
    _nodes[key] = _Node(
      path: normalizePath(path),
      isDir: false,
      modified: modified ?? clock.now(),
      attrs: attrs,
      fileId: _nextFileId++,
      data: data,
      size: data?.length ?? size ?? 0,
    );
    _linkToParent(key);
  }

  /// Creates [newPath] as a hard link to [existing] (same file ID and data).
  void addHardLink(String existing, String newPath) {
    final src = _nodes[pathKey(existing)]!;
    _ensureParents(newPath);
    final key = pathKey(newPath);
    _nodes[key] = _Node(
      path: normalizePath(newPath),
      isDir: false,
      modified: src.modified,
      attrs: src.attrs,
      fileId: src.fileId,
      data: src.data,
      size: src.size,
    );
    _linkToParent(key);
  }

  /// Simulates editing a file in place (changes size and mtime; parent
  /// directory mtime is unchanged, as on NTFS).
  void modifyFile(String path, {int? size, DateTime? modified}) {
    final n = _nodes[pathKey(path)]!;
    if (size != null) {
      n
        ..data = null
        ..size = size;
    }
    n.modified = modified ?? clock.now();
  }

  void setAttrs(String path, FileAttrs attrs) =>
      _nodes[pathKey(path)]!.attrs = attrs;

  void lock(String path) => _locked.add(pathKey(path));
  void unlock(String path) => _locked.remove(pathKey(path));
  void deny(String path) => _denied.add(pathKey(path));

  bool exists(String path) => _nodes.containsKey(pathKey(path));

  /// Removes a file behind the engine's back (user deleted it in Explorer).
  void externalDelete(String path) => _removeNode(pathKey(path));

  /// Moves a file behind the engine's back.
  void externalMove(String from, String to) {
    _ensureParents(to);
    _rename(from, to);
  }

  // ------------------------------------------------------------ interface

  @override
  FsEntry? stat(String path) {
    final n = _nodes[pathKey(path)];
    if (n == null) return null;
    final serial = volumeSerialOf(path);
    if (serial == null) return null;
    return _entry(n, serial);
  }

  @override
  List<FsEntry> list(String dirPath) {
    final key = pathKey(dirPath);
    final n = _nodes[key];
    final serial = volumeSerialOf(dirPath);
    if (n == null || !n.isDir || serial == null) {
      throw FsException(FsErrorCode.notFound, dirPath);
    }
    if (_denied.contains(key)) {
      throw FsException(FsErrorCode.accessDenied, dirPath);
    }
    return [for (final c in n.children) _entry(_nodes[c]!, serial)];
  }

  @override
  int? volumeSerialOf(String path) => _volumes[pathKey(driveRoot(path))];

  @override
  void move(String from, String to) {
    mutationLog.add('move $from -> $to');
    final fromKey = pathKey(from);
    final n = _nodes[fromKey];
    if (n == null || volumeSerialOf(from) == null) {
      throw FsException(FsErrorCode.notFound, from);
    }
    if (_locked.contains(fromKey)) throw FsException(FsErrorCode.inUse, from);
    if (_denied.contains(fromKey)) {
      throw FsException(FsErrorCode.accessDenied, from);
    }
    if (volumeSerialOf(from) != volumeSerialOf(to)) {
      throw FsException(FsErrorCode.crossVolume, from);
    }
    if (_nodes.containsKey(pathKey(to))) {
      throw FsException(FsErrorCode.alreadyExists, to);
    }
    if (!_nodes.containsKey(pathKey(winPath.dirname(to)))) {
      throw FsException(FsErrorCode.notFound, winPath.dirname(to));
    }
    _rename(from, to);
  }

  @override
  void delete(String path) {
    mutationLog.add('delete $path');
    final key = pathKey(path);
    final n = _nodes[key];
    if (n == null) throw FsException(FsErrorCode.notFound, path);
    if (n.isDir) throw FsException(FsErrorCode.io, path, 'is a directory');
    if (_locked.contains(key)) throw FsException(FsErrorCode.inUse, path);
    if (_denied.contains(key)) {
      throw FsException(FsErrorCode.accessDenied, path);
    }
    _removeNode(key);
  }

  @override
  void dehydrate(String path) {
    mutationLog.add('dehydrate $path');
    final n = _nodes[pathKey(path)];
    if (n == null) throw FsException(FsErrorCode.notFound, path);
    n.attrs = n.attrs.copyWith(onlineOnly: true, pinned: false);
  }

  @override
  void createDirectories(String path) => addDir(path);

  @override
  Uint8List readBytes(String path) {
    final n = _nodes[pathKey(path)];
    if (n == null || n.isDir) throw FsException(FsErrorCode.notFound, path);
    return Uint8List.fromList(n.data ?? Uint8List(n.size));
  }

  @override
  void writeBytes(String path, List<int> bytes) {
    final key = pathKey(path);
    final existing = _nodes[key];
    if (existing != null) {
      existing
        ..data = Uint8List.fromList(bytes)
        ..size = bytes.length
        ..modified = clock.now();
      return;
    }
    addFile(path, bytes: bytes);
  }

  @override
  void replaceFile(String source, String target) {
    final targetKey = pathKey(target);
    if (_nodes.containsKey(targetKey)) _removeNode(targetKey);
    _rename(source, target);
  }

  // -------------------------------------------------------------- helpers

  FsEntry _entry(_Node n, int serial) => FsEntry(
        path: n.path,
        isDirectory: n.isDir,
        size: n.isDir ? 0 : n.size,
        modified: n.modified,
        volumeSerial: serial,
        attrs: n.attrs,
        fileId: n.fileId,
      );

  void _ensureParents(String path) {
    final parent = winPath.dirname(normalizePath(path));
    if (samePath(parent, path)) return; // drive root
    if (!_nodes.containsKey(pathKey(parent))) addDir(parent);
  }

  void _linkToParent(String key) {
    final parentKey = pathKey(winPath.dirname(_nodes[key]!.path));
    final parent = _nodes[parentKey];
    if (parent == null || parentKey == key) return;
    parent.children.add(key);
    parent.modified = clock.now();
  }

  void _unlinkFromParent(String key) {
    final parentKey = pathKey(winPath.dirname(_nodes[key]!.path));
    final parent = _nodes[parentKey];
    if (parent == null) return;
    parent.children.remove(key);
    parent.modified = clock.now();
  }

  void _removeNode(String key) {
    final n = _nodes[key];
    if (n == null) return;
    for (final c in n.children.toList()) {
      _removeNode(c);
    }
    _unlinkFromParent(key);
    _nodes.remove(key);
    _locked.remove(key);
  }

  void _rename(String from, String to) {
    final fromKey = pathKey(from);
    final n = _nodes[fromKey]!;
    _unlinkFromParent(fromKey);
    _nodes.remove(fromKey);
    final toKey = pathKey(to);
    n.path = normalizePath(to);
    _nodes[toKey] = n;
    _linkToParent(toKey);
    if (n.isDir) _rekeyChildren(n);
  }

  void _rekeyChildren(_Node dir) {
    final old = dir.children.toList();
    dir.children.clear();
    for (final ck in old) {
      final child = _nodes.remove(ck)!;
      child.path = winPath.join(dir.path, winPath.basename(child.path));
      final nk = pathKey(child.path);
      _nodes[nk] = child;
      dir.children.add(nk);
      if (child.isDir) _rekeyChildren(child);
    }
  }
}
