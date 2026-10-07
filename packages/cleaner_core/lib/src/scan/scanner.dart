import '../index/index_db.dart';
import '../model/models.dart';
import '../model/path_key.dart';
import '../platform/platform_fs.dart';
import 'categorizer.dart';

/// What to scan and what to leave alone.
final class ScanRequest {
  ScanRequest({
    required List<String> roots,
    List<String> exclusions = const [],
    List<String> trashRoots = const [],
    List<String> protectedRoots = const [],
  })  : roots = _dedupeRoots(roots),
        exclusions = List.unmodifiable(exclusions.map(normalizePath)),
        trashRoots = List.unmodifiable(trashRoots.map(normalizePath)),
        protectedRoots = List.unmodifiable(protectedRoots.map(normalizePath));

  final List<String> roots;
  final List<String> exclusions;
  final List<String> trashRoots;
  final List<String> protectedRoots;

  /// Drops roots nested inside other roots so nothing is walked twice.
  static List<String> _dedupeRoots(List<String> roots) {
    final norm = roots.map(normalizePath).toList();
    return List.unmodifiable([
      for (final r in norm)
        if (!norm.any((o) => !samePath(o, r) && isWithin(o, r))) r,
    ]);
  }
}

final class ScanProgress {
  const ScanProgress({
    required this.files,
    required this.dirs,
    required this.bytes,
    required this.unreadableDirs,
    required this.currentDir,
  });

  final int files;
  final int dirs;
  final int bytes;
  final int unreadableDirs;
  final String currentDir;
}

final class ScanSummary {
  const ScanSummary({
    required this.runId,
    required this.status,
    required this.files,
    required this.bytes,
    required this.unreadableDirs,
    required this.forgotten,
  });

  final int runId;
  final RunStatus status;
  final int files;
  final int bytes;
  final int unreadableDirs;

  /// Index rows dropped because the file no longer exists.
  final int forgotten;
}

/// Walks scan roots and records every file's metadata in the index.
///
/// Reads directory listings only, never file contents. Never descends into
/// links, hidden system folders, dot-folders, exclusions, trash roots or
/// protected roots.
///
/// Every folder is listed on every scan: on NTFS a folder's modified time
/// does not change when a file inside it is edited, so it can't be used to
/// skip work safely. Unchanged rows are cheap upserts.
final class Scanner {
  Scanner({
    required PlatformFs fs,
    required IndexDb db,
    required Categorizer categorizer,
    required Clock clock,
    this.batchSize = 1000,
  })  : _fs = fs,
        _db = db,
        _categorizer = categorizer,
        _clock = clock;

  final PlatformFs _fs;
  final IndexDb _db;
  final Categorizer _categorizer;
  final Clock _clock;
  final int batchSize;

  ScanSummary run(
    ScanRequest request, {
    CancelToken? cancel,
    void Function(ScanProgress)? onProgress,
  }) {
    _db.markStaleRunsInterrupted();
    final runId = _db.startScanRun(_clock.now());
    final batch = <ScannedFile>[];
    var files = 0, dirs = 0, bytes = 0, unreadable = 0;
    var cancelled = false;
    final scannedRoots = <String>[];

    void flush(String currentDir) {
      _db.upsertScanned(batch, runId);
      batch.clear();
      onProgress?.call(ScanProgress(
        files: files,
        dirs: dirs,
        bytes: bytes,
        unreadableDirs: unreadable,
        currentDir: currentDir,
      ));
    }

    outer:
    for (final root in request.roots) {
      if (_fs.stat(root) == null) continue; // drive not mounted
      scannedRoots.add(root);
      final stack = <String>[root];
      while (stack.isNotEmpty) {
        if (cancel?.isCancelled ?? false) {
          cancelled = true;
          break outer;
        }
        final dir = stack.removeLast();
        dirs++;
        final List<FsEntry> entries;
        try {
          entries = _fs.list(dir);
        } on FsException {
          unreadable++;
          continue;
        }
        for (final e in entries) {
          if (e.isDirectory) {
            if (_skipDir(e, request)) continue;
            stack.add(e.path);
            continue;
          }
          if (_skipFile(e)) continue;
          final c = _categorizer.categorize(e.path);
          batch.add(ScannedFile(
            path: e.path,
            volumeSerial: e.volumeSerial,
            size: e.size,
            modified: e.modified,
            category: c.category,
            isProtected: c.isProtected,
            cloudSynced: c.cloudSynced,
            onlineOnly: e.attrs.onlineOnly,
            pinned: e.attrs.pinned,
            fileId: e.fileId,
          ));
          files++;
          if (!e.attrs.onlineOnly) bytes += e.size;
          if (batch.length >= batchSize) flush(dir);
        }
      }
    }
    flush(request.roots.isEmpty ? '' : request.roots.last);

    var forgotten = 0;
    final RunStatus status;
    if (cancelled) {
      status = RunStatus.interrupted;
    } else {
      // Only a complete walk proves that unseen files are really gone.
      forgotten = _db.deleteUnseen(runId, scannedRoots);
      status = RunStatus.complete;
    }
    _db.finishScanRun(
      runId,
      now: _clock.now(),
      status: status,
      files: files,
      bytes: bytes,
      unreadableDirs: unreadable,
    );
    return ScanSummary(
      runId: runId,
      status: status,
      files: files,
      bytes: bytes,
      unreadableDirs: unreadable,
      forgotten: forgotten,
    );
  }

  bool _skipDir(FsEntry e, ScanRequest r) {
    if (e.attrs.isLink) return true;
    if (e.attrs.hidden && e.attrs.system) return true;
    if (winPath.basename(e.path).startsWith('.')) return true;
    bool under(List<String> roots) =>
        roots.any((x) => isWithinOrEqual(x, e.path));
    return under(r.exclusions) || under(r.trashRoots) || under(r.protectedRoots);
  }

  bool _skipFile(FsEntry e) {
    if (e.attrs.isLink) return true;
    if (e.attrs.hidden && e.attrs.system) return true; // desktop.ini etc.
    return false;
  }
}
