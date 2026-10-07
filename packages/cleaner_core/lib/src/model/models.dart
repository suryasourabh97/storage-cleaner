/// File categories shown in the UI (spec §5.1).
enum Category {
  downloads,
  documents,
  videos,
  audio,
  pictures,
  archives,
  installers,
  other;

  static Category parse(String name) =>
      Category.values.firstWhere((c) => c.name == name, orElse: () => other);
}

/// Lifecycle of an indexed file (spec §6).
enum ItemState {
  indexed,
  moving,
  trashed,
  restoring,
  deleting,
  freeing,
  freed,
  missing;

  static ItemState parse(String name) => ItemState.values.byName(name);
}

/// File-system attributes the engine cares about.
///
/// [isLink] means a *name-surrogate* reparse point (junction, symbolic link,
/// volume mount point). OneDrive placeholders are also reparse points on
/// Windows, but they are not links and must not be reported as such; the
/// Windows adapter classifies reparse tags accordingly.
final class FileAttrs {
  const FileAttrs({
    this.hidden = false,
    this.system = false,
    this.isLink = false,
    this.onlineOnly = false,
    this.pinned = false,
  });

  final bool hidden;
  final bool system;
  final bool isLink;

  /// Cloud placeholder whose contents are not stored locally.
  final bool onlineOnly;

  /// "Always keep on this device" (OneDrive).
  final bool pinned;

  static const none = FileAttrs();

  FileAttrs copyWith({
    bool? hidden,
    bool? system,
    bool? isLink,
    bool? onlineOnly,
    bool? pinned,
  }) =>
      FileAttrs(
        hidden: hidden ?? this.hidden,
        system: system ?? this.system,
        isLink: isLink ?? this.isLink,
        onlineOnly: onlineOnly ?? this.onlineOnly,
        pinned: pinned ?? this.pinned,
      );
}

/// One directory-listing entry or `stat` result.
final class FsEntry {
  const FsEntry({
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
    required this.volumeSerial,
    this.attrs = FileAttrs.none,
    this.fileId,
  });

  final String path;
  final bool isDirectory;
  final int size;

  /// Last-modified time, UTC.
  final DateTime modified;
  final int volumeSerial;
  final FileAttrs attrs;

  /// NTFS file index; equal for hard links to the same data.
  final int? fileId;
}

/// Why an operation on one file did not happen.
enum SkipReason {
  notFound,
  changedSinceScan,
  inUse,
  accessDenied,
  crossVolume,
  guardRejected,
  alreadyExists,
  trashUnavailable,
  notConfirmed,
  volumeUnavailable,
  wrongState,
  ioError,
}

/// Result of an operation on a single file. Expected per-file failures are
/// values, not exceptions.
sealed class OpOutcome {
  const OpOutcome(this.path);
  final String path;
}

final class OpDone extends OpOutcome {
  const OpDone(super.path, {this.newPath});

  /// Where the file is now, for moves.
  final String? newPath;
}

final class OpSkipped extends OpOutcome {
  const OpSkipped(super.path, this.reason, [this.detail]);
  final SkipReason reason;
  final String? detail;

  @override
  String toString() => 'OpSkipped($path, $reason${detail == null ? '' : ', $detail'})';
}

/// Summary of a batch operation.
final class BatchResult {
  BatchResult(this.outcomes);
  final List<OpOutcome> outcomes;

  Iterable<OpDone> get done => outcomes.whereType<OpDone>();
  Iterable<OpSkipped> get skipped => outcomes.whereType<OpSkipped>();
  int get doneCount => done.length;
  int get skippedCount => skipped.length;
}

/// Cooperative cancellation for long operations.
final class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// Injected time source; core code never calls `DateTime.now()` directly.
abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now().toUtc();
}

/// Milliseconds since epoch, UTC, as stored in the index.
int toMillis(DateTime t) => t.toUtc().millisecondsSinceEpoch;
DateTime fromMillis(int ms) =>
    DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
