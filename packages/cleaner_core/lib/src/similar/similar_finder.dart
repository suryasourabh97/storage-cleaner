import '../duplicates/duplicate_finder.dart'
    show AnalysisPhase, AnalysisProgress;
import '../duplicates/keep_rules.dart';
import '../index/index_db.dart';
import '../model/models.dart';
import '../model/path_key.dart';
import '../platform/platform_fs.dart';
import '../scan/categorizer.dart';
import '../trash/trash_manager.dart';
import 'image_decoder.dart';
import 'perceptual_hash.dart';

/// Matching thresholds (spec D16). Calibrated against the labelled image
/// set in the Windows CI tests.
final class SimilarityThresholds {
  const SimilarityThresholds({
    this.maxHashDistance = 4,
    this.maxAspectDifference = 0.01,
    this.maxColorDistance = 12,
  });

  /// Both pHash and dHash must be within this many bits.
  final int maxHashDistance;

  /// Relative aspect-ratio difference above which a copy counts as cropped.
  final double maxAspectDifference;

  /// Colour-signature distance above which a copy counts as filtered.
  final double maxColorDistance;
}

/// Image types compared (see [Categorizer.imageExt]).
const photoExtensions = Categorizer.imageExt;

/// Smallest photo file considered. The spec said 100 KB, but messaging-app
/// copies (the most common resized copy) are often 50–100 KB; icons are
/// excluded by [minPhotoSide] instead.
const minPhotoBytes = 20 * 1024;
const minPhotoSide = 256;

final class SimilarSummary {
  const SimilarSummary({
    required this.status,
    required this.groups,
    required this.compared,
    required this.fingerprinted,
    required this.unsupported,
    required this.unreadable,
    required this.tooSmall,
  });

  final RunStatus status;
  final int groups;

  /// Photos available for comparison after this run (new and earlier).
  final int compared;

  /// Photos newly fingerprinted in this run.
  final int fingerprinted;

  /// HEIC and other formats without a decoder.
  final int unsupported;
  final int unreadable;
  final int tooSmall;
}

/// Near-identical copies of one photo. [members] starts with the copy that
/// is kept by default (highest quality).
final class SimilarGroup {
  SimilarGroup({required this.members, required this.edited});

  final List<FileRecord> members;

  /// A member looks cropped or filtered: nothing is preselected and the user
  /// chooses (spec D17).
  final bool edited;

  FileRecord get best => members.first;

  int get reclaimable =>
      members.skip(1).fold(0, (s, m) => s + m.size);

  /// Default removals: every copy except the best, unless edited.
  Set<int> get defaultRemovals =>
      edited ? <int>{} : {for (final m in members.skip(1)) m.id};
}

/// Fingerprints photos (ADR-004, ADR-007). Fingerprints are stored with each
/// file's size and modified time, so later runs only decode new or changed
/// photos.
final class SimilarPhotoFinder {
  SimilarPhotoFinder({
    required PlatformFs fs,
    required IndexDb db,
    required ImageDecoder decoder,
    required Clock clock,
  })  : _fs = fs,
        _db = db,
        _decoder = decoder,
        _clock = clock;

  final PlatformFs _fs;
  final IndexDb _db;
  final ImageDecoder _decoder;
  final Clock _clock;

  Future<SimilarSummary> run({
    List<String> exclusions = const [],
    CancelToken? cancel,
    void Function(AnalysisProgress)? onProgress,
    SimilarityThresholds thresholds = const SimilarityThresholds(),
    KeepRules? rules,
  }) async {
    final runId = _db.startAnalysisRun('similar', _clock.now());
    var fingerprinted = 0, unsupported = 0, unreadable = 0, tooSmall = 0;
    var status = RunStatus.complete;

    final todo = [
      for (final r in _db.photoCandidates(minPhotoBytes))
        if (Categorizer.isImagePath(
              r.path,
              picturesFolder: rules?.folders.pictures,
            ) &&
            r.width == null &&
            !exclusions.any((e) => isWithinOrEqual(e, r.path)))
          r,
    ];

    for (var i = 0; i < todo.length; i++) {
      if (cancel?.isCancelled ?? false) {
        status = RunStatus.interrupted;
        break;
      }
      final r = todo[i];
      final st = _fs.stat(r.path);
      if (st == null ||
          st.size != r.size ||
          toMillis(st.modified) != toMillis(r.modified)) {
        continue; // changed since the scan
      }
      final result = await _decoder.decode(r.path);
      switch (result) {
        case DecodeOk(:final image):
          if (image.width < minPhotoSide || image.height < minPhotoSide) {
            _db.setFingerprint(r.id, width: image.width, height: image.height);
            tooSmall++;
          } else {
            _db.setFingerprint(
              r.id,
              width: image.width,
              height: image.height,
              phash: perceptualHash(image.gray),
              dhash: differenceHash(image.gray),
              colorSig: image.colorSig,
            );
            fingerprinted++;
          }
        case DecodeFailed(reason: DecodeFailure.unsupportedFormat):
          unsupported++;
        case DecodeFailed():
          unreadable++;
      }
      onProgress?.call(AnalysisProgress(
        phase: AnalysisPhase.fingerprinting,
        done: i + 1,
        total: todo.length,
        bytesRead: 0,
      ));
    }

    final groups = status == RunStatus.complete
        ? similarPhotoGroups(
            _db,
            exclusions: exclusions,
            thresholds: thresholds,
            rules: rules,
          ).length
        : 0;
    _db.finishAnalysisRun(
      runId,
      now: _clock.now(),
      status: status,
      bytesRead: 0,
      groupsFound: groups,
    );
    return SimilarSummary(
      status: status,
      groups: groups,
      compared: _db.fingerprintedPhotos().length,
      fingerprinted: fingerprinted,
      unsupported: unsupported,
      unreadable: unreadable,
      tooSmall: tooSmall,
    );
  }
}

/// Best copy first: most pixels, then larger file (less compression), then
/// location (KeepRules), then oldest, then shortest path.
int compareQuality(FileRecord a, FileRecord b, KeepRules? rules) {
  final pa = (a.width ?? 0) * (a.height ?? 0);
  final pb = (b.width ?? 0) * (b.height ?? 0);
  if (pa != pb) return pb.compareTo(pa);
  if (a.size != b.size) return b.size.compareTo(a.size);
  if (rules != null) return rules.compare(a, b);
  final byAge = a.modified.compareTo(b.modified);
  if (byAge != 0) return byAge;
  return a.path.length.compareTo(b.path.length);
}

/// Groups near-identical photos from stored fingerprints (ADR-004):
/// exact duplicates are collapsed first, candidate pairs come from an
/// 8-bucket index on the pHash (two hashes within 7 bits share at least one
/// byte), and a photo joins a group only if it matches the group's best
/// photo directly.
List<SimilarGroup> similarPhotoGroups(
  IndexDb db, {
  List<String> exclusions = const [],
  SimilarityThresholds thresholds = const SimilarityThresholds(),
  KeepRules? rules,
}) {
  var photos = [
    for (final r in db.fingerprintedPhotos())
      if (!exclusions.any((e) => isWithinOrEqual(e, r.path))) r,
  ]..sort((a, b) => compareQuality(a, b, rules));

  // Exact duplicates belong to the Duplicates tab: keep one per content.
  final seenHash = <String>{};
  photos = [
    for (final p in photos)
      if (p.fullHash == null || seenHash.add(p.fullHash!)) p,
  ];

  final buckets = <int, List<int>>{};
  for (var i = 0; i < photos.length; i++) {
    final h = photos[i].phash!;
    for (var b = 0; b < 8; b++) {
      buckets.putIfAbsent((b << 8) | ((h >> (b * 8)) & 0xFF), () => []).add(i);
    }
  }

  bool matches(FileRecord a, FileRecord b) =>
      hamming(a.phash!, b.phash!) <= thresholds.maxHashDistance &&
      hamming(a.dhash!, b.dhash!) <= thresholds.maxHashDistance;

  bool editedVersus(FileRecord leader, FileRecord m) {
    final la = leader.width! / leader.height!;
    final ma = m.width! / m.height!;
    if ((ma - la).abs() / la > thresholds.maxAspectDifference) return true;
    final lc = leader.colorSig, mc = m.colorSig;
    if (lc == null || mc == null) return false;
    return colorDistance(lc, mc) > thresholds.maxColorDistance;
  }

  final assigned = <int>{};
  final groups = <SimilarGroup>[];
  for (var i = 0; i < photos.length; i++) {
    if (assigned.contains(i)) continue;
    assigned.add(i);
    final leader = photos[i];
    final candidates = <int>{};
    final h = leader.phash!;
    for (var b = 0; b < 8; b++) {
      candidates.addAll(buckets[(b << 8) | ((h >> (b * 8)) & 0xFF)] ?? const []);
    }
    final members = <FileRecord>[leader];
    for (final j in candidates.toList()..sort()) {
      if (assigned.contains(j)) continue;
      if (matches(leader, photos[j])) {
        members.add(photos[j]);
        assigned.add(j);
      }
    }
    if (members.length > 1) {
      groups.add(SimilarGroup(
        members: members,
        edited: members.skip(1).any((m) => editedVersus(leader, m)),
      ));
    }
  }
  groups.sort((a, b) => b.reclaimable.compareTo(a.reclaimable));
  return groups;
}

/// What the user chose for one similar-photo group.
final class SimilarRemoval {
  const SimilarRemoval({
    required this.group,
    required this.keepId,
    required this.removeIds,
  });

  final SimilarGroup group;
  final int keepId;
  final Set<int> removeIds;
}

/// Moves the chosen copies to the trash. Refuses selections that keep no
/// photo; skips the whole group if the kept photo is gone, changed, or no
/// longer has the fingerprint it was grouped by.
BatchResult removeSimilar(
  List<SimilarRemoval> removals, {
  required IndexDb db,
  required PlatformFs fs,
  required TrashManager trash,
}) {
  final outcomes = <OpOutcome>[];
  for (final rm in removals) {
    final memberIds = {for (final m in rm.group.members) m.id};
    final byId = {for (final m in rm.group.members) m.id: m};
    final valid = rm.removeIds.isNotEmpty &&
        memberIds.containsAll(rm.removeIds) &&
        memberIds.contains(rm.keepId) &&
        !rm.removeIds.contains(rm.keepId) &&
        KeepRules.keepsAtLeastOne(memberIds, rm.removeIds);
    if (!valid) {
      for (final id in rm.removeIds) {
        outcomes.add(
            OpSkipped(byId[id]?.path ?? '$id', SkipReason.wrongState, 'invalid selection'));
      }
      continue;
    }
    final grouped = byId[rm.keepId]!;
    final kept = db.byId(rm.keepId);
    final st = kept == null ? null : fs.stat(kept.path);
    final keptOk = kept != null &&
        kept.state == ItemState.indexed &&
        kept.phash == grouped.phash &&
        st != null &&
        st.size == kept.size &&
        toMillis(st.modified) == toMillis(kept.modified);
    if (!keptOk) {
      for (final id in rm.removeIds) {
        outcomes.add(OpSkipped(byId[id]!.path, SkipReason.keptCopyChanged));
      }
      continue;
    }
    final still = <int>[];
    for (final id in rm.removeIds) {
      final now = db.byId(id);
      if (now != null && now.phash == byId[id]!.phash) {
        still.add(id);
      } else {
        outcomes.add(OpSkipped(byId[id]!.path, SkipReason.changedSinceScan));
      }
    }
    outcomes.addAll(trash.moveToTrash(still).outcomes);
  }
  return BatchResult(outcomes);
}
