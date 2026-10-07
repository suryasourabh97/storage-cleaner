import '../model/models.dart';
import '../model/path_key.dart';
import '../platform/platform_fs.dart';
import 'path_guard.dart';

/// Proof that the user confirmed permanent deletion of a specific set of
/// paths. Create one only from a confirmation dialog's "Delete permanently"
/// action. Each path can be used once.
final class DeletionConfirmation {
  DeletionConfirmation.userConfirmed(Iterable<String> paths)
      : _remaining = {for (final p in paths) pathKey(p)};

  final Set<String> _remaining;

  bool covers(String path) => _remaining.contains(pathKey(path));

  void _consume(String path) => _remaining.remove(pathKey(path));
}

/// The only component allowed to change user files (ADR-006).
final class FileMutator {
  FileMutator(this._fs, this._guard);

  final PlatformFs _fs;
  final PathGuard _guard;

  PathGuard get guard => _guard;

  /// Same-volume rename from [from] to [to]. Creates [to]'s parent folder if
  /// needed. Never copies.
  OpOutcome move(String from, String to) {
    final g1 = _guard.check(from);
    if (g1 is GuardRejected) {
      return OpSkipped(from, SkipReason.guardRejected, g1.why);
    }
    final g2 = _guard.check(to);
    if (g2 is GuardRejected) {
      return OpSkipped(from, SkipReason.guardRejected, 'target: ${g2.why}');
    }
    final fromVol = _fs.volumeSerialOf(from);
    final toVol = _fs.volumeSerialOf(to);
    if (fromVol == null || toVol == null) {
      return OpSkipped(from, SkipReason.volumeUnavailable);
    }
    if (fromVol != toVol) return OpSkipped(from, SkipReason.crossVolume);
    if (_fs.stat(to) != null) return OpSkipped(from, SkipReason.alreadyExists);
    try {
      _fs.createDirectories(winPath.dirname(to));
      _fs.move(from, to);
      return OpDone(from, newPath: normalizePath(to));
    } on FsException catch (e) {
      return OpSkipped(from, _reasonFor(e.code), e.message);
    }
  }

  /// Permanently deletes [path]; requires the user's confirmation for it.
  OpOutcome deletePermanently(String path, DeletionConfirmation confirmation) {
    if (!confirmation.covers(path)) {
      return OpSkipped(path, SkipReason.notConfirmed);
    }
    final g = _guard.check(path);
    if (g is GuardRejected) {
      return OpSkipped(path, SkipReason.guardRejected, g.why);
    }
    try {
      _fs.delete(path);
      confirmation._consume(path);
      return OpDone(path);
    } on FsException catch (e) {
      return OpSkipped(path, _reasonFor(e.code), e.message);
    }
  }

  /// OneDrive "Free up space": keep the file in the cloud, drop the local
  /// copy. Non-destructive.
  OpOutcome dehydrate(String path) {
    final g = _guard.check(path);
    if (g is GuardRejected) {
      return OpSkipped(path, SkipReason.guardRejected, g.why);
    }
    try {
      _fs.dehydrate(path);
      return OpDone(path);
    } on FsException catch (e) {
      return OpSkipped(path, _reasonFor(e.code), e.message);
    }
  }

  static SkipReason _reasonFor(FsErrorCode code) => switch (code) {
        FsErrorCode.notFound => SkipReason.notFound,
        FsErrorCode.alreadyExists => SkipReason.alreadyExists,
        FsErrorCode.inUse => SkipReason.inUse,
        FsErrorCode.accessDenied => SkipReason.accessDenied,
        FsErrorCode.crossVolume => SkipReason.crossVolume,
        FsErrorCode.notEmpty || FsErrorCode.io => SkipReason.ioError,
      };
}
