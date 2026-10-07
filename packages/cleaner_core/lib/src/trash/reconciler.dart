import '../index/index_db.dart';
import '../model/models.dart';
import '../model/path_key.dart';
import '../platform/platform_fs.dart';
import '../scan/categorizer.dart';
import 'manifest.dart';
import 'trash_manager.dart';

final class ReconcileReport {
  int movesCompleted = 0;
  int movesReverted = 0;
  int restoresCompleted = 0;
  int restoresReverted = 0;
  int deletesCompleted = 0;
  int deletesReverted = 0;
  int missing = 0;

  /// Trashed rows whose file was removed from the trash by hand.
  int vanished = 0;

  /// Trash items recovered from manifests (index lost or app reinstalled).
  int rebuilt = 0;

  /// Index rows that were missing from their manifest and were added.
  int manifestRepaired = 0;
}

/// Runs at every launch, before anything else touches the trash
/// (spec §12, ADR-002): finishes or reverts operations interrupted by a
/// crash, and makes the index and the manifests agree with the disk.
final class Reconciler {
  Reconciler({
    required PlatformFs fs,
    required IndexDb db,
    required TrashManager trash,
    required Categorizer categorizer,
    required Clock clock,
  })  : _fs = fs,
        _db = db,
        _trash = trash,
        _categorizer = categorizer,
        _clock = clock;

  final PlatformFs _fs;
  final IndexDb _db;
  final TrashManager _trash;
  final Categorizer _categorizer;
  final Clock _clock;

  bool _exists(String path) => _fs.stat(path) != null;

  ReconcileReport run({required List<String> trashRoots}) {
    final report = ReconcileReport();
    final dirty = <String, TrashManifest>{};

    TrashManifest manifestOf(String path) {
      final root = _trash.locator.trashRootFor(path);
      final m = _trash.manifestFor(root);
      dirty[pathKey(root)] = m;
      return m;
    }

    // 1. Interrupted moves to trash.
    for (final r in _db.inState(ItemState.moving)) {
      final pending = r.pendingPath;
      if (_fs.volumeSerialOf(r.path) == null) continue;
      if (pending != null && _exists(pending) && !_exists(r.path)) {
        final at = _clock.now();
        manifestOf(pending).add(ManifestItem(
          trashPath: pending,
          originalPath: r.path,
          size: r.size,
          trashedAt: at,
        ));
        _db.markTrashed(
          r.id,
          trashPath: pending,
          originalPath: r.path,
          trashedAt: at,
        );
        report.movesCompleted++;
      } else if (_exists(r.path)) {
        _db.revertToIndexed(r.id);
        report.movesReverted++;
      } else {
        _db.markMissing(r.id);
        report.missing++;
      }
    }

    // 2. Interrupted restores.
    for (final r in _db.inState(ItemState.restoring)) {
      final pending = r.pendingPath;
      if (_fs.volumeSerialOf(r.path) == null) continue;
      if (pending != null && _exists(pending) && !_exists(r.path)) {
        manifestOf(r.path).remove(r.path);
        _db.markRestored(r.id, pending);
        report.restoresCompleted++;
      } else if (_exists(r.path)) {
        _toTrashed(r);
        report.restoresReverted++;
      } else {
        _db.markMissing(r.id);
        report.missing++;
      }
    }

    // 3. Interrupted permanent deletes. If the file is still there the
    // delete did not happen; it needs a fresh confirmation.
    for (final r in _db.inState(ItemState.deleting)) {
      if (_fs.volumeSerialOf(r.path) == null) continue;
      if (_exists(r.path)) {
        _toTrashed(r);
        report.deletesReverted++;
      } else {
        manifestOf(r.path).remove(r.path);
        _db.deleteRow(r.id);
        report.deletesCompleted++;
      }
    }

    // 4. Make index and manifests agree, per available trash root.
    final trashed = _db.inState(ItemState.trashed);
    for (final root in trashRoots) {
      if (_fs.volumeSerialOf(root) == null || !_exists(root)) continue;
      final manifest = _trash.manifestFor(root);
      dirty[pathKey(root)] = manifest;

      final rowsHere = [
        for (final r in trashed)
          if (isWithin(root, r.path)) r,
      ];
      final rowKeys = {for (final r in rowsHere) pathKey(r.path)};

      for (final r in rowsHere) {
        if (!_exists(r.path)) {
          manifest.remove(r.path);
          _db.deleteRow(r.id);
          report.vanished++;
        } else if (!manifest.contains(r.path)) {
          manifest.add(ManifestItem(
            trashPath: r.path,
            originalPath: r.originalPath!,
            size: r.size,
            trashedAt: r.trashedAt ?? _clock.now(),
          ));
          report.manifestRepaired++;
        }
      }

      for (final item in manifest.items.toList()) {
        if (rowKeys.contains(pathKey(item.trashPath))) continue;
        final st = _fs.stat(item.trashPath);
        if (st == null) {
          manifest.remove(item.trashPath);
          continue;
        }
        _db.insertTrashed(
          trashPath: item.trashPath,
          originalPath: item.originalPath,
          volumeSerial: st.volumeSerial,
          size: st.size,
          modified: st.modified,
          category: _categorizer.categorize(item.originalPath).category,
          trashedAt: item.trashedAt,
        );
        report.rebuilt++;
      }
    }

    for (final m in dirty.values) {
      m.save();
    }
    return report;
  }

  void _toTrashed(FileRecord r) => _db.markTrashed(
        r.id,
        trashPath: r.path,
        originalPath: r.originalPath!,
        trashedAt: r.trashedAt ?? _clock.now(),
      );
}
