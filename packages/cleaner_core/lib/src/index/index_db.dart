import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import '../model/models.dart';
import '../model/path_key.dart';

/// One row of the `files` table.
final class FileRecord {
  const FileRecord({
    required this.id,
    required this.path,
    required this.volumeSerial,
    required this.size,
    required this.modified,
    required this.category,
    required this.state,
    this.originalPath,
    this.pendingPath,
    this.isProtected = false,
    this.cloudSynced = false,
    this.onlineOnly = false,
    this.pinned = false,
    this.trashedAt,
    this.fileId,
    this.sampleHash,
    this.fullHash,
    this.width,
    this.height,
    this.phash,
    this.dhash,
    this.colorSig,
  });

  final int id;

  /// Where the file is now (the trash path once trashed).
  final String path;

  /// Where it came from, once trashed.
  final String? originalPath;

  /// Target of an in-flight move or restore.
  final String? pendingPath;
  final int volumeSerial;
  final int size;
  final DateTime modified;
  final Category category;
  final bool isProtected;
  final bool cloudSynced;
  final bool onlineOnly;
  final bool pinned;
  final ItemState state;
  final DateTime? trashedAt;
  final int? fileId;

  /// Duplicate pipeline hashes; valid while size and modified time match.
  final String? sampleHash;
  final String? fullHash;

  /// Photo fingerprint (similar photos); valid while size and modified time
  /// match. Width/height are set even for photos too small to compare.
  final int? width;
  final int? height;
  final int? phash;
  final int? dhash;
  final Uint8List? colorSig;
}

/// Values the scanner writes for each file it sees.
final class ScannedFile {
  const ScannedFile({
    required this.path,
    required this.volumeSerial,
    required this.size,
    required this.modified,
    required this.category,
    required this.isProtected,
    required this.cloudSynced,
    required this.onlineOnly,
    required this.pinned,
    this.fileId,
  });

  final String path;
  final int volumeSerial;
  final int size;
  final DateTime modified;
  final Category category;
  final bool isProtected;
  final bool cloudSynced;
  final bool onlineOnly;
  final bool pinned;
  final int? fileId;
}

enum RunStatus { running, complete, interrupted }

final class ScanRun {
  const ScanRun({
    required this.id,
    required this.startedAt,
    required this.status,
    this.endedAt,
    this.files = 0,
    this.bytes = 0,
    this.unreadableDirs = 0,
  });

  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final RunStatus status;
  final int files;
  final int bytes;
  final int unreadableDirs;
}

/// Local SQLite index (ADR-003). A rebuildable cache: trash state can be
/// recovered from manifests and scan data from a rescan.
final class IndexDb {
  IndexDb._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    _migrate();
  }

  factory IndexDb.open(String filePath) {
    final db = sqlite3.open(filePath);
    db.execute('PRAGMA journal_mode = WAL');
    // The app reads while a background isolate scans into the same file.
    db.execute('PRAGMA busy_timeout = 5000');
    return IndexDb._(db);
  }

  factory IndexDb.inMemory() => IndexDb._(sqlite3.openInMemory());

  final Database _db;

  static const schemaVersion = 1;

  void close() => _db.dispose();

  // ------------------------------------------------------------ schema

  void _migrate() {
    final version = _db.userVersion;
    if (version > schemaVersion) {
      throw StateError('Index schema $version is newer than this app.');
    }
    if (version < 1) {
      _db.execute('''
        CREATE TABLE files (
          id INTEGER PRIMARY KEY,
          path TEXT NOT NULL,
          path_key TEXT NOT NULL UNIQUE,
          original_path TEXT,
          pending_path TEXT,
          volume_serial INTEGER NOT NULL,
          size_bytes INTEGER NOT NULL,
          modified_at INTEGER NOT NULL,
          category TEXT NOT NULL,
          protected INTEGER NOT NULL DEFAULT 0,
          cloud_synced INTEGER NOT NULL DEFAULT 0,
          online_only INTEGER NOT NULL DEFAULT 0,
          pinned INTEGER NOT NULL DEFAULT 0,
          state TEXT NOT NULL,
          trashed_at INTEGER,
          file_id INTEGER,
          sample_hash TEXT,
          full_hash TEXT,
          hashed_at INTEGER,
          phash INTEGER,
          dhash INTEGER,
          width INTEGER,
          height INTEGER,
          color_sig BLOB,
          seen_run INTEGER
        );
        CREATE INDEX files_state_modified ON files(state, modified_at);
        CREATE INDEX files_state_size ON files(state, size_bytes);
        CREATE INDEX files_state_trashed ON files(state, trashed_at);
        CREATE INDEX files_size_hash ON files(size_bytes, full_hash);

        CREATE TABLE scan_runs (
          id INTEGER PRIMARY KEY,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          status TEXT NOT NULL,
          files INTEGER NOT NULL DEFAULT 0,
          bytes INTEGER NOT NULL DEFAULT 0,
          unreadable_dirs INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE exclusions (
          path_key TEXT PRIMARY KEY,
          path TEXT NOT NULL
        );

        CREATE TABLE analysis_runs (
          id INTEGER PRIMARY KEY,
          type TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          status TEXT NOT NULL,
          bytes_read INTEGER NOT NULL DEFAULT 0,
          groups_found INTEGER NOT NULL DEFAULT 0
        );

        CREATE TABLE cache_runs (
          id INTEGER PRIMARY KEY,
          app TEXT NOT NULL,
          cleaned_at INTEGER NOT NULL,
          bytes_freed INTEGER NOT NULL
        );
      ''');
      _db.userVersion = 1;
    }
  }

  // ------------------------------------------------------- transactions

  T transaction<T>(T Function() body) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = body();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  // ---------------------------------------------------------- scan runs

  int startScanRun(DateTime now) {
    _db.execute(
      'INSERT INTO scan_runs(started_at, status) VALUES (?, ?)',
      [toMillis(now), RunStatus.running.name],
    );
    return _db.lastInsertRowId;
  }

  void finishScanRun(
    int id, {
    required DateTime now,
    required RunStatus status,
    required int files,
    required int bytes,
    required int unreadableDirs,
  }) {
    _db.execute(
      'UPDATE scan_runs SET ended_at = ?, status = ?, files = ?, bytes = ?, '
      'unreadable_dirs = ? WHERE id = ?',
      [toMillis(now), status.name, files, bytes, unreadableDirs, id],
    );
  }

  /// Marks runs left `running` by a crash as interrupted.
  void markStaleRunsInterrupted() {
    _db.execute(
      "UPDATE scan_runs SET status = 'interrupted' WHERE status = 'running'",
    );
    _db.execute(
      "UPDATE analysis_runs SET status = 'interrupted' "
      "WHERE status = 'running'",
    );
  }

  ScanRun? latestScanRun() {
    final rows = _db.select('SELECT * FROM scan_runs ORDER BY id DESC LIMIT 1');
    if (rows.isEmpty) return null;
    final r = rows.first;
    final ended = r['ended_at'] as int?;
    return ScanRun(
      id: r['id'] as int,
      startedAt: fromMillis(r['started_at'] as int),
      endedAt: ended == null ? null : fromMillis(ended),
      status: RunStatus.values.byName(r['status'] as String),
      files: r['files'] as int,
      bytes: r['bytes'] as int,
      unreadableDirs: r['unreadable_dirs'] as int,
    );
  }

  // ------------------------------------------------------------ scanning

  /// Inserts or refreshes scanned files. Rows that are not `indexed`
  /// (trashed, moving, ...) are left untouched. Cached hashes and
  /// fingerprints are kept only if size and modified time are unchanged.
  void upsertScanned(List<ScannedFile> batch, int runId) {
    if (batch.isEmpty) return;
    final stmt = _db.prepare('''
      INSERT INTO files(path, path_key, volume_serial, size_bytes, modified_at,
        category, protected, cloud_synced, online_only, pinned, state,
        file_id, seen_run)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'indexed', ?, ?)
      ON CONFLICT(path_key) DO UPDATE SET
        path = excluded.path,
        volume_serial = excluded.volume_serial,
        category = excluded.category,
        protected = excluded.protected,
        cloud_synced = excluded.cloud_synced,
        online_only = excluded.online_only,
        pinned = excluded.pinned,
        file_id = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN COALESCE(excluded.file_id, files.file_id)
          ELSE excluded.file_id END,
        seen_run = excluded.seen_run,
        sample_hash = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN files.sample_hash ELSE NULL END,
        full_hash = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN files.full_hash ELSE NULL END,
        phash = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN files.phash ELSE NULL END,
        dhash = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN files.dhash ELSE NULL END,
        width = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN files.width ELSE NULL END,
        height = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN files.height ELSE NULL END,
        color_sig = CASE WHEN files.size_bytes = excluded.size_bytes
          AND files.modified_at = excluded.modified_at
          THEN files.color_sig ELSE NULL END,
        size_bytes = excluded.size_bytes,
        modified_at = excluded.modified_at
      WHERE files.state = 'indexed'
    ''');
    try {
      transaction(() {
        for (final f in batch) {
          stmt.execute([
            normalizePath(f.path),
            pathKey(f.path),
            f.volumeSerial,
            f.size,
            toMillis(f.modified),
            f.category.name,
            _b(f.isProtected),
            _b(f.cloudSynced),
            _b(f.onlineOnly),
            _b(f.pinned),
            f.fileId,
            runId,
          ]);
        }
      });
    } finally {
      stmt.dispose();
    }
  }

  /// After a complete scan: forget `indexed` files under [roots] that were
  /// not seen in run [runId] (deleted or moved outside the app).
  int deleteUnseen(int runId, List<String> roots) {
    var removed = 0;
    transaction(() {
      for (final root in roots) {
        final prefix = '${pathKey(root)}\\';
        _db.execute(
          '''DELETE FROM files WHERE state = 'indexed'
             AND (seen_run IS NULL OR seen_run != ?)
             AND substr(path_key, 1, length(?)) = ?''',
          [runId, prefix, prefix],
        );
        removed += _db.updatedRows;
      }
    });
    return removed;
  }

  // -------------------------------------------------------------- reads

  FileRecord? byId(int id) {
    final rows = _db.select('SELECT * FROM files WHERE id = ?', [id]);
    return rows.isEmpty ? null : _record(rows.first);
  }

  FileRecord? byPath(String path) {
    final rows =
        _db.select('SELECT * FROM files WHERE path_key = ?', [pathKey(path)]);
    return rows.isEmpty ? null : _record(rows.first);
  }

  /// Local `indexed` files, optionally older than [modifiedBefore] and/or
  /// at least [minSize] bytes. Largest first.
  List<FileRecord> indexedFiles({DateTime? modifiedBefore, int? minSize}) {
    final where = <String>["state = 'indexed'", 'online_only = 0'];
    final args = <Object?>[];
    if (modifiedBefore != null) {
      where.add('modified_at < ?');
      args.add(toMillis(modifiedBefore));
    }
    if (minSize != null) {
      where.add('size_bytes >= ?');
      args.add(minSize);
    }
    final rows = _db.select(
      'SELECT * FROM files WHERE ${where.join(' AND ')} '
      'ORDER BY size_bytes DESC',
      args,
    );
    return [for (final r in rows) _record(r)];
  }

  List<FileRecord> inState(ItemState state) {
    final rows = _db.select(
      'SELECT * FROM files WHERE state = ? ORDER BY id',
      [state.name],
    );
    return [for (final r in rows) _record(r)];
  }

  int countAll() => _db.select('SELECT COUNT(*) AS n FROM files').first['n'] as int;

  // ------------------------------------------------------ state changes

  void markMoving(int id, String target) => _db.execute(
        "UPDATE files SET state = 'moving', pending_path = ? WHERE id = ?",
        [normalizePath(target), id],
      );

  void markRestoring(int id, String target) => _db.execute(
        "UPDATE files SET state = 'restoring', pending_path = ? WHERE id = ?",
        [normalizePath(target), id],
      );

  void markDeleting(int id) => _db.execute(
        "UPDATE files SET state = 'deleting' WHERE id = ?",
        [id],
      );

  /// Back to `indexed` at its current path (failed or reverted move).
  void revertToIndexed(int id) => _db.execute(
        "UPDATE files SET state = 'indexed', pending_path = NULL WHERE id = ?",
        [id],
      );

  void markTrashed(
    int id, {
    required String trashPath,
    required String originalPath,
    required DateTime trashedAt,
  }) =>
      _db.execute(
        '''UPDATE files SET state = 'trashed', path = ?, path_key = ?,
           original_path = ?, pending_path = NULL, trashed_at = ?
           WHERE id = ?''',
        [
          normalizePath(trashPath),
          pathKey(trashPath),
          normalizePath(originalPath),
          toMillis(trashedAt),
          id,
        ],
      );

  /// File is back in user space at [path].
  void markRestored(int id, String path) {
    // A stale indexed row may already exist at the target path.
    _db.execute(
      "DELETE FROM files WHERE path_key = ? AND id != ? AND state = 'indexed'",
      [pathKey(path), id],
    );
    _db.execute(
      '''UPDATE files SET state = 'indexed', path = ?, path_key = ?,
         original_path = NULL, pending_path = NULL, trashed_at = NULL
         WHERE id = ?''',
      [normalizePath(path), pathKey(path), id],
    );
  }

  void markMissing(int id) => _db.execute(
        "UPDATE files SET state = 'missing', pending_path = NULL WHERE id = ?",
        [id],
      );

  void updateStat(int id, {required int size, required DateTime modified}) =>
      _db.execute(
        'UPDATE files SET size_bytes = ?, modified_at = ? WHERE id = ?',
        [size, toMillis(modified), id],
      );

  void deleteRow(int id) =>
      _db.execute('DELETE FROM files WHERE id = ?', [id]);

  /// Inserts a trashed item recovered from a manifest. Returns its id.
  int insertTrashed({
    required String trashPath,
    required String originalPath,
    required int volumeSerial,
    required int size,
    required DateTime modified,
    required Category category,
    required DateTime trashedAt,
  }) {
    _db.execute(
      '''INSERT INTO files(path, path_key, original_path, volume_serial,
         size_bytes, modified_at, category, state, trashed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'trashed', ?)''',
      [
        normalizePath(trashPath),
        pathKey(trashPath),
        normalizePath(originalPath),
        volumeSerial,
        size,
        toMillis(modified),
        category.name,
        toMillis(trashedAt),
      ],
    );
    return _db.lastInsertRowId;
  }

  // --------------------------------------------------------- exclusions

  List<String> exclusions() => [
        for (final r in _db.select('SELECT path FROM exclusions ORDER BY path'))
          r['path'] as String,
      ];

  void addExclusion(String path) => _db.execute(
        'INSERT OR IGNORE INTO exclusions(path_key, path) VALUES (?, ?)',
        [pathKey(path), normalizePath(path)],
      );

  void removeExclusion(String path) => _db.execute(
        'DELETE FROM exclusions WHERE path_key = ?',
        [pathKey(path)],
      );

  // ------------------------------------------------------------ mapping

  static int _b(bool v) => v ? 1 : 0;

  static FileRecord _record(Row r) {
    final trashed = r['trashed_at'] as int?;
    return FileRecord(
      id: r['id'] as int,
      path: r['path'] as String,
      originalPath: r['original_path'] as String?,
      pendingPath: r['pending_path'] as String?,
      volumeSerial: r['volume_serial'] as int,
      size: r['size_bytes'] as int,
      modified: fromMillis(r['modified_at'] as int),
      category: Category.parse(r['category'] as String),
      isProtected: (r['protected'] as int) == 1,
      cloudSynced: (r['cloud_synced'] as int) == 1,
      onlineOnly: (r['online_only'] as int) == 1,
      pinned: (r['pinned'] as int) == 1,
      state: ItemState.parse(r['state'] as String),
      trashedAt: trashed == null ? null : fromMillis(trashed),
      fileId: r['file_id'] as int?,
      sampleHash: r['sample_hash'] as String?,
      fullHash: r['full_hash'] as String?,
      width: r['width'] as int?,
      height: r['height'] as int?,
      phash: r['phash'] as int?,
      dhash: r['dhash'] as int?,
      colorSig: r['color_sig'] as Uint8List?,
    );
  }

  // ------------------------------------------------------ similar photos

  /// Local indexed files of at least [minSize] bytes (the caller filters by
  /// extension). Online-only files are never candidates.
  List<FileRecord> photoCandidates(int minSize) {
    final rows = _db.select('''
      SELECT * FROM files
      WHERE state = 'indexed' AND online_only = 0 AND size_bytes >= ?
      ORDER BY id
    ''', [minSize]);
    return [for (final r in rows) _record(r)];
  }

  void setFingerprint(
    int id, {
    required int width,
    required int height,
    int? phash,
    int? dhash,
    Uint8List? colorSig,
  }) =>
      _db.execute(
        'UPDATE files SET width = ?, height = ?, phash = ?, dhash = ?, '
        'color_sig = ? WHERE id = ?',
        [width, height, phash, dhash, colorSig, id],
      );

  /// Indexed local photos that have a fingerprint.
  List<FileRecord> fingerprintedPhotos() {
    final rows = _db.select('''
      SELECT * FROM files
      WHERE state = 'indexed' AND online_only = 0 AND phash IS NOT NULL
      ORDER BY id
    ''');
    return [for (final r in rows) _record(r)];
  }

  // -------------------------------------------------------- duplicates

  /// Local indexed files of at least [minSize] bytes whose size is shared
  /// with at least one other such file. Online-only files are never
  /// candidates (reading them would download them).
  List<FileRecord> duplicateCandidates(int minSize) {
    final rows = _db.select('''
      SELECT * FROM files
      WHERE state = 'indexed' AND online_only = 0 AND size_bytes >= ?
        AND size_bytes IN (
          SELECT size_bytes FROM files
          WHERE state = 'indexed' AND online_only = 0 AND size_bytes >= ?
          GROUP BY size_bytes HAVING COUNT(*) > 1)
      ORDER BY size_bytes DESC, id
    ''', [minSize, minSize]);
    return [for (final r in rows) _record(r)];
  }

  /// Files whose full hash is shared with another file of the same size.
  List<FileRecord> fullHashMatches(int minSize) {
    final rows = _db.select('''
      SELECT * FROM files
      WHERE state = 'indexed' AND online_only = 0 AND full_hash IS NOT NULL
        AND size_bytes >= ?
        AND (size_bytes, full_hash) IN (
          SELECT size_bytes, full_hash FROM files
          WHERE state = 'indexed' AND online_only = 0
            AND full_hash IS NOT NULL AND size_bytes >= ?
          GROUP BY size_bytes, full_hash HAVING COUNT(*) > 1)
      ORDER BY size_bytes DESC, full_hash, id
    ''', [minSize, minSize]);
    return [for (final r in rows) _record(r)];
  }

  void setFileId(int id, int? fileId) => _db.execute(
        'UPDATE files SET file_id = ? WHERE id = ?',
        [fileId, id],
      );

  void setSampleHash(int id, String hash) => _db.execute(
        'UPDATE files SET sample_hash = ? WHERE id = ?',
        [hash, id],
      );

  void setFullHash(int id, String hash, DateTime at) => _db.execute(
        'UPDATE files SET full_hash = ?, hashed_at = ? WHERE id = ?',
        [hash, toMillis(at), id],
      );

  int startAnalysisRun(String type, DateTime now) {
    _db.execute(
      'INSERT INTO analysis_runs(type, started_at, status) VALUES (?, ?, ?)',
      [type, toMillis(now), RunStatus.running.name],
    );
    return _db.lastInsertRowId;
  }

  void finishAnalysisRun(
    int id, {
    required DateTime now,
    required RunStatus status,
    required int bytesRead,
    required int groupsFound,
  }) =>
      _db.execute(
        'UPDATE analysis_runs SET ended_at = ?, status = ?, bytes_read = ?, '
        'groups_found = ? WHERE id = ?',
        [toMillis(now), status.name, bytesRead, groupsFound, id],
      );

  /// When the last analysis of [type] ended, and how.
  (DateTime, RunStatus)? latestAnalysis(String type) {
    final rows = _db.select(
      'SELECT * FROM analysis_runs WHERE type = ? ORDER BY id DESC LIMIT 1',
      [type],
    );
    if (rows.isEmpty) return null;
    final r = rows.first;
    final at = (r['ended_at'] as int?) ?? (r['started_at'] as int);
    final status = RunStatus.values.byName(r['status'] as String);
    return (fromMillis(at), status);
  }
}
