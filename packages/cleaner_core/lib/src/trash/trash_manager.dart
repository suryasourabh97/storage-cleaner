import '../index/index_db.dart';
import '../model/models.dart';
import '../model/path_key.dart';
import '../platform/platform_fs.dart';
import '../safety/file_mutator.dart';
import 'manifest.dart';

/// Where each drive's trash lives (ADR-002).
final class TrashLocator {
  TrashLocator({required String userProfile})
      : userProfile = normalizePath(userProfile);

  final String userProfile;

  String get _systemDrive => driveRoot(userProfile);

  /// Trash root for files on the same drive as [path].
  String trashRootFor(String path) {
    final drive = driveRoot(path);
    return samePath(drive, _systemDrive)
        ? winPath.join(userProfile, trashFolderName)
        : winPath.join(drive, trashFolderName);
  }

  /// Folder the trash mirrors: the user profile on the system drive (so
  /// `Downloads\a.pdf` stays short), otherwise the drive root.
  String mirrorBaseFor(String path) =>
      isWithin(userProfile, path) ? userProfile : driveRoot(path);

  /// Trash location for [path], before collision handling.
  String mirrorPathFor(String path) => winPath.join(
        trashRootFor(path),
        winPath.relative(normalizePath(path), from: mirrorBaseFor(path)),
      );

  /// Trash roots for the given drive roots.
  List<String> trashRootsFor(Iterable<String> driveRoots) =>
      [for (final d in driveRoots) trashRootFor(d)];
}

/// How to resolve a restore whose original location is taken.
sealed class RestoreChoice {
  const RestoreChoice();
}

/// Restore next to the existing file with a ` (n)` suffix.
final class KeepBoth extends RestoreChoice {
  const KeepBoth();
}

/// Restore into a folder the user picked.
final class RestoreInto extends RestoreChoice {
  const RestoreInto(this.folder);
  final String folder;
}

sealed class RestoreResult {
  const RestoreResult();
}

final class Restored extends RestoreResult {
  const Restored(this.path);
  final String path;
}

/// The original location is occupied; ask the user for a [RestoreChoice].
final class RestoreConflict extends RestoreResult {
  const RestoreConflict(this.originalPath);
  final String originalPath;
}

final class RestoreFailed extends RestoreResult {
  const RestoreFailed(this.reason, [this.detail]);
  final SkipReason reason;
  final String? detail;
}

/// Moves files to the trash, restores them and deletes them permanently
/// (spec flows 4, 6, 8).
final class TrashManager {
  TrashManager({
    required PlatformFs fs,
    required IndexDb db,
    required FileMutator mutator,
    required TrashLocator locator,
    required Clock clock,
  })  : _fs = fs,
        _db = db,
        _mutator = mutator,
        _locator = locator,
        _clock = clock;

  final PlatformFs _fs;
  final IndexDb _db;
  final FileMutator _mutator;
  final TrashLocator _locator;
  final Clock _clock;

  final Map<String, TrashManifest> _manifests = {};

  TrashLocator get locator => _locator;

  TrashManifest manifestFor(String trashRoot) => _manifests.putIfAbsent(
        pathKey(trashRoot),
        () => TrashManifest.load(_fs, trashRoot),
      );

  // ---------------------------------------------------------- move

  /// Moves the given indexed files to the trash. Each file is re-checked
  /// first; files that changed since the scan are skipped.
  BatchResult moveToTrash(Iterable<int> ids, {CancelToken? cancel}) {
    final outcomes = <OpOutcome>[];
    final touched = <String, TrashManifest>{};
    try {
      for (final id in ids) {
        if (cancel?.isCancelled ?? false) break;
        final r = _db.byId(id);
        if (r == null) continue;
        outcomes.add(_moveOne(r, touched));
      }
    } finally {
      for (final m in touched.values) {
        m.save();
      }
    }
    return BatchResult(outcomes);
  }

  OpOutcome _moveOne(FileRecord r, Map<String, TrashManifest> touched) {
    if (r.state != ItemState.indexed) {
      return OpSkipped(r.path, SkipReason.wrongState, r.state.name);
    }
    final now = _fs.stat(r.path);
    if (now == null) {
      _db.deleteRow(r.id);
      return OpSkipped(r.path, SkipReason.notFound);
    }
    // The index stores milliseconds; NTFS has 100 ns precision.
    if (now.size != r.size || toMillis(now.modified) != toMillis(r.modified)) {
      _db.updateStat(r.id, size: now.size, modified: now.modified);
      return OpSkipped(r.path, SkipReason.changedSinceScan);
    }

    final trashRoot = _locator.trashRootFor(r.path);
    try {
      TrashManifest.ensureTrashRoot(_fs, trashRoot);
    } on FsException catch (e) {
      return OpSkipped(r.path, SkipReason.trashUnavailable, e.toString());
    }
    final manifest = manifestFor(trashRoot);
    final target = _freeTarget(_locator.mirrorPathFor(r.path), manifest);

    _db.markMoving(r.id, target);
    final outcome = _mutator.move(r.path, target);
    if (outcome is OpSkipped) {
      _db.revertToIndexed(r.id);
      return outcome;
    }
    final trashedAt = _clock.now();
    manifest.add(ManifestItem(
      trashPath: target,
      originalPath: r.path,
      size: r.size,
      trashedAt: trashedAt,
    ));
    touched[pathKey(trashRoot)] = manifest;
    _db.markTrashed(
      r.id,
      trashPath: target,
      originalPath: r.path,
      trashedAt: trashedAt,
    );
    return outcome;
  }

  String _freeTarget(String desired, TrashManifest manifest) {
    var candidate = desired;
    var n = 1;
    while (_fs.stat(candidate) != null || manifest.contains(candidate)) {
      candidate = withCollisionSuffix(desired, n++);
    }
    return candidate;
  }

  // ------------------------------------------------------- restore

  /// Restores a trashed file to where it came from. Returns
  /// [RestoreConflict] if that location is taken and no [choice] was given.
  RestoreResult restore(int id, {RestoreChoice? choice}) {
    final r = _db.byId(id);
    if (r == null || r.state != ItemState.trashed || r.originalPath == null) {
      return const RestoreFailed(SkipReason.wrongState);
    }
    if (_fs.volumeSerialOf(r.path) == null) {
      return const RestoreFailed(SkipReason.volumeUnavailable);
    }
    if (_fs.stat(r.path) == null) {
      _db.markMissing(r.id);
      return const RestoreFailed(SkipReason.notFound);
    }

    final original = r.originalPath!;
    if (choice == null && _fs.stat(original) != null) {
      return RestoreConflict(original);
    }
    final target = switch (choice) {
      null => original,
      KeepBoth() => _freeUserTarget(original),
      RestoreInto(:final folder) => _freeUserTarget(
          winPath.join(folder, winPath.basename(original)),
        ),
    };

    _db.markRestoring(r.id, target);
    final outcome = _mutator.move(r.path, target);
    if (outcome is OpSkipped) {
      _db.markTrashedBack(r);
      return RestoreFailed(outcome.reason, outcome.detail);
    }
    final trashRoot = _locator.trashRootFor(r.path);
    final manifest = manifestFor(trashRoot)..remove(r.path);
    manifest.save();
    _db.markRestored(r.id, target);
    return Restored(normalizePath(target));
  }

  String _freeUserTarget(String desired) {
    var candidate = desired;
    var n = 1;
    while (_fs.stat(candidate) != null) {
      candidate = withCollisionSuffix(desired, n++);
    }
    return candidate;
  }

  // ------------------------------------------------ permanent delete

  /// Permanently deletes trashed files the user confirmed.
  BatchResult deletePermanently(
    Iterable<int> ids,
    DeletionConfirmation confirmation,
  ) {
    final outcomes = <OpOutcome>[];
    final touched = <String, TrashManifest>{};
    try {
      for (final id in ids) {
        final r = _db.byId(id);
        if (r == null) continue;
        if (r.state != ItemState.trashed) {
          outcomes.add(OpSkipped(r.path, SkipReason.wrongState, r.state.name));
          continue;
        }
        if (_fs.volumeSerialOf(r.path) == null) {
          outcomes.add(OpSkipped(r.path, SkipReason.volumeUnavailable));
          continue;
        }
        final trashRoot = _locator.trashRootFor(r.path);
        final manifest = manifestFor(trashRoot);
        if (_fs.stat(r.path) == null) {
          // Already gone (deleted by hand): just forget it.
          manifest.remove(r.path);
          touched[pathKey(trashRoot)] = manifest;
          _db.deleteRow(r.id);
          outcomes.add(OpDone(r.path));
          continue;
        }
        _db.markDeleting(r.id);
        final outcome = _mutator.deletePermanently(r.path, confirmation);
        if (outcome is OpSkipped) {
          _db.markTrashedBack(r);
          outcomes.add(outcome);
          continue;
        }
        manifest.remove(r.path);
        touched[pathKey(trashRoot)] = manifest;
        _db.deleteRow(r.id);
        outcomes.add(outcome);
      }
    } finally {
      for (final m in touched.values) {
        m.save();
      }
    }
    return BatchResult(outcomes);
  }
}

extension on IndexDb {
  /// Puts a row back to `trashed` after a failed restore or delete.
  void markTrashedBack(FileRecord r) => markTrashed(
        r.id,
        trashPath: r.path,
        originalPath: r.originalPath!,
        trashedAt: r.trashedAt!,
      );
}
