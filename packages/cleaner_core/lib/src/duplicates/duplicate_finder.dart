import '../index/index_db.dart';
import '../model/models.dart';
import '../model/path_key.dart';
import '../platform/platform_fs.dart';
import '../scan/categorizer.dart';
import '../trash/trash_manager.dart';
import 'hasher.dart';
import 'keep_rules.dart';

/// Minimum file sizes offered for the duplicate finder (spec §5.2).
enum DuplicateMinSize {
  kb100(100 * 1024),
  mb1(1024 * 1024),
  mb10(10 * 1024 * 1024),
  mb100(100 * 1024 * 1024);

  const DuplicateMinSize(this.bytes);
  final int bytes;

  static const defaultValue = DuplicateMinSize.mb1;
}

enum AnalysisPhase { comparingSizes, sampling, hashing, fingerprinting }

final class AnalysisProgress {
  const AnalysisProgress({
    required this.phase,
    required this.done,
    required this.total,
    required this.bytesRead,
  });

  final AnalysisPhase phase;
  final int done;
  final int total;
  final int bytesRead;
}

final class AnalysisSummary {
  const AnalysisSummary({
    required this.status,
    required this.groups,
    required this.bytesRead,
    required this.filesRead,
    required this.unreadable,
    required this.changed,
  });

  final RunStatus status;
  final int groups;
  final int bytesRead;
  final int filesRead;

  /// Files that could not be read (locked, access denied).
  final int unreadable;

  /// Files that changed since the scan (skipped; rescan to include).
  final int changed;
}

/// A set of files with identical content.
final class DuplicateGroup {
  DuplicateGroup({
    required this.hash,
    required this.size,
    required this.members,
    required this.suggestedKeep,
  });

  final String hash;
  final int size;

  /// Best copy first (see [KeepRules]).
  final List<FileRecord> members;
  final FileRecord suggestedKeep;

  /// Space freed by keeping one copy.
  int get reclaimable => size * (members.length - 1);
}

/// Finds files with identical content (ADR-004): exact size, then a sample
/// hash, then a full SHA-256. Hashes are stored in the index with the file's
/// size and modified time, so a later run only reads new or changed files;
/// an interrupted run resumes where it stopped.
final class DuplicateFinder {
  DuplicateFinder({
    required PlatformFs fs,
    required IndexDb db,
    required Clock clock,
    ContentHasher? hasher,
  })  : _fs = fs,
        _db = db,
        _clock = clock,
        _hasher = hasher ?? ContentHasher(fs);

  final PlatformFs _fs;
  final IndexDb _db;
  final Clock _clock;
  final ContentHasher _hasher;

  AnalysisSummary run({
    required int minSize,
    List<String> exclusions = const [],
    CancelToken? cancel,
    void Function(AnalysisProgress)? onProgress,
  }) {
    final runId = _db.startAnalysisRun('duplicates', _clock.now());
    var bytesRead = 0, filesRead = 0, unreadable = 0, changed = 0;
    var status = RunStatus.complete;

    bool cancelled() => cancel?.isCancelled ?? false;

    try {
      // 1. Same-size groups, without exclusions and hard links.
      final candidates = [
        for (final r in _db.duplicateCandidates(_floor(minSize)))
          if (_qualifies(r, minSize) &&
              !exclusions.any((e) => isWithinOrEqual(e, r.path)))
            r,
      ];
      final bySize = <int, List<FileRecord>>{};
      for (final r in candidates) {
        bySize.putIfAbsent(r.size, () => []).add(r);
      }
      final sizeGroups = <List<FileRecord>>[];
      var done = 0;
      for (final group in bySize.values) {
        if (cancelled()) throw const HashCancelled();
        done += group.length;
        if (group.length < 2) continue;
        final unique = _withoutHardLinks(group);
        if (unique.length > 1) sizeGroups.add(unique);
        onProgress?.call(AnalysisProgress(
          phase: AnalysisPhase.comparingSizes,
          done: done,
          total: candidates.length,
          bytesRead: bytesRead,
        ));
      }

      // 2. Sample hashes.
      final sampleTotal = sizeGroups.fold(0, (s, g) => s + g.length);
      var sampled = 0;
      final sampleGroups = <List<FileRecord>>[];
      for (final group in sizeGroups) {
        final bySample = <String, List<FileRecord>>{};
        for (final r in group) {
          if (cancelled()) throw const HashCancelled();
          sampled++;
          var hash = r.sampleHash;
          if (hash == null) {
            if (!_unchanged(r)) {
              changed++;
              continue;
            }
            try {
              hash = _hasher.sample(r.path, r.size);
              final read = r.size <= _hasher.sampleSize * 3
                  ? r.size
                  : _hasher.sampleSize * 3;
              bytesRead += read;
              filesRead++;
              _db.setSampleHash(r.id, hash);
            } on FsException {
              unreadable++;
              continue;
            }
          }
          bySample.putIfAbsent(hash, () => []).add(r);
          onProgress?.call(AnalysisProgress(
            phase: AnalysisPhase.sampling,
            done: sampled,
            total: sampleTotal,
            bytesRead: bytesRead,
          ));
        }
        sampleGroups.addAll(bySample.values.where((g) => g.length > 1));
      }

      // 3. Full hashes for files whose samples match.
      final fullTotal = sampleGroups.fold(0, (s, g) => s + g.length);
      var hashed = 0;
      for (final group in sampleGroups) {
        for (final r in group) {
          if (cancelled()) throw const HashCancelled();
          hashed++;
          if (r.fullHash != null) continue;
          if (!_unchanged(r)) {
            changed++;
            continue;
          }
          try {
            final hash = _hasher.full(
              r.path,
              r.size,
              cancel: cancel,
              onBytes: (n) => bytesRead += n,
            );
            filesRead++;
            if (_unchanged(r)) {
              _db.setFullHash(r.id, hash, _clock.now());
            } else {
              changed++;
            }
          } on FsException {
            unreadable++;
          }
          onProgress?.call(AnalysisProgress(
            phase: AnalysisPhase.hashing,
            done: hashed,
            total: fullTotal,
            bytesRead: bytesRead,
          ));
        }
      }
    } on HashCancelled {
      status = RunStatus.interrupted;
    }

    final groups = status == RunStatus.complete
        ? duplicateGroups(_db, minSize: minSize, exclusions: exclusions).length
        : 0;
    _db.finishAnalysisRun(
      runId,
      now: _clock.now(),
      status: status,
      bytesRead: bytesRead,
      groupsFound: groups,
    );
    return AnalysisSummary(
      status: status,
      groups: groups,
      bytesRead: bytesRead,
      filesRead: filesRead,
      unreadable: unreadable,
      changed: changed,
    );
  }

  /// Hard links share storage: keep one entry per (volume, file ID). File
  /// IDs are fetched lazily, only for files that share a size.
  List<FileRecord> _withoutHardLinks(List<FileRecord> group) {
    final seen = <(int, int)>{};
    final out = <FileRecord>[];
    for (final r in group) {
      var id = r.fileId;
      if (id == null) {
        id = _fs.fileIdOf(r.path);
        _db.setFileId(r.id, id);
      }
      if (id == null || seen.add((r.volumeSerial, id))) out.add(r);
    }
    return out;
  }

  /// The file on disk still has the size and date the index recorded.
  bool _unchanged(FileRecord r) {
    final st = _fs.stat(r.path);
    return st != null &&
        st.size == r.size &&
        toMillis(st.modified) == toMillis(r.modified);
  }
}

/// Smallest image file compared, whatever the general minimum (images
/// matter even when small: screenshots, messaging copies).
const minImageBytes = 20 * 1024;

int _floor(int minSize) => minSize < minImageBytes ? minSize : minImageBytes;

/// General files must reach [minSize]; image files only [minImageBytes].
bool _qualifies(FileRecord r, int minSize) =>
    r.size >= minSize ||
    (r.size >= minImageBytes &&
        Categorizer.imageExt.contains(winPath.extension(r.path).toLowerCase()));

/// Current duplicate groups from stored hashes, largest reclaimable space
/// first. Hard links are collapsed; each group's best copy comes first.
List<DuplicateGroup> duplicateGroups(
  IndexDb db, {
  required int minSize,
  List<String> exclusions = const [],
  KeepRules? rules,
}) {
  final byKey = <(int, String), List<FileRecord>>{};
  for (final r in db.fullHashMatches(_floor(minSize))) {
    if (!_qualifies(r, minSize)) continue;
    if (exclusions.any((e) => isWithinOrEqual(e, r.path))) continue;
    byKey.putIfAbsent((r.size, r.fullHash!), () => []).add(r);
  }
  final groups = <DuplicateGroup>[];
  for (final MapEntry(key: (size, hash), value: rows) in byKey.entries) {
    final seen = <(int, int)>{};
    final members = [
      for (final r in rows)
        if (r.fileId == null || seen.add((r.volumeSerial, r.fileId!))) r,
    ];
    if (members.length < 2) continue;
    if (rules != null) members.sort(rules.compare);
    groups.add(DuplicateGroup(
      hash: hash,
      size: size,
      members: members,
      suggestedKeep: members.first,
    ));
  }
  groups.sort((a, b) => b.reclaimable.compareTo(a.reclaimable));
  return groups;
}

/// What the user chose for one group.
final class DuplicateRemoval {
  const DuplicateRemoval({
    required this.group,
    required this.keepId,
    required this.removeIds,
  });

  final DuplicateGroup group;
  final int keepId;
  final Set<int> removeIds;
}

/// Moves the chosen extra copies to the trash. Before touching a group it
/// re-checks that the copy being kept still exists, unchanged, with the same
/// hash; otherwise the whole group is skipped. A selection that would leave
/// no copy is refused (spec §13.2).
BatchResult removeDuplicates(
  List<DuplicateRemoval> removals, {
  required IndexDb db,
  required PlatformFs fs,
  required TrashManager trash,
}) {
  final outcomes = <OpOutcome>[];
  for (final rm in removals) {
    final memberIds = {for (final m in rm.group.members) m.id};
    final valid = rm.removeIds.isNotEmpty &&
        memberIds.containsAll(rm.removeIds) &&
        memberIds.contains(rm.keepId) &&
        !rm.removeIds.contains(rm.keepId) &&
        KeepRules.keepsAtLeastOne(memberIds, rm.removeIds);
    if (!valid) {
      for (final id in rm.removeIds) {
        outcomes.add(OpSkipped('$id', SkipReason.wrongState, 'invalid selection'));
      }
      continue;
    }

    final kept = db.byId(rm.keepId);
    final keptStat = kept == null ? null : fs.stat(kept.path);
    final keptOk = kept != null &&
        kept.state == ItemState.indexed &&
        kept.fullHash == rm.group.hash &&
        keptStat != null &&
        keptStat.size == kept.size &&
        toMillis(keptStat.modified) == toMillis(kept.modified);
    if (!keptOk) {
      for (final id in rm.removeIds) {
        final r = db.byId(id);
        outcomes.add(OpSkipped(r?.path ?? '$id', SkipReason.keptCopyChanged));
      }
      continue;
    }

    // Each removed copy must still carry the group's hash.
    final stillSame = [
      for (final id in rm.removeIds)
        if (db.byId(id) case final r? when r.fullHash == rm.group.hash) id,
    ];
    for (final id in rm.removeIds.difference(stillSame.toSet())) {
      final r = db.byId(id);
      outcomes.add(OpSkipped(r?.path ?? '$id', SkipReason.changedSinceScan));
    }
    outcomes.addAll(trash.moveToTrash(stillSame).outcomes);
  }
  return BatchResult(outcomes);
}
