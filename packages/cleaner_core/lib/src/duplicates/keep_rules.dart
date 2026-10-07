import '../index/index_db.dart';
import '../model/path_key.dart';
import '../scan/categorizer.dart';

/// Chooses which copy to keep (spec D14 for duplicates) and enforces that a
/// selection always keeps at least one copy.
final class KeepRules {
  const KeepRules(this.folders);

  final KnownFolders folders;

  static const _tempLike = {'temp', 'tmp', 'cache', 'caches', 'old', 'backup'};

  /// 3: in OneDrive (removing it would also delete it from the cloud).
  /// 2: in Documents, Pictures, Desktop, Videos or Music.
  /// 1: anywhere else.
  /// 0: in Downloads or a temp-like folder.
  int locationScore(FileRecord r) {
    if (r.cloudSynced) return 3;
    bool inside(String? f) => f != null && isWithin(f, r.path);
    if (inside(folders.downloads)) return 0;
    final segments = winPath.split(winPath.dirname(r.path).toLowerCase());
    if (segments.any(_tempLike.contains)) return 0;
    if ([
      folders.documents,
      folders.pictures,
      folders.desktop,
      folders.videos,
      folders.music,
    ].any(inside)) {
      return 2;
    }
    return 1;
  }

  /// Best-first order: location score, then oldest, then shortest path.
  int compare(FileRecord a, FileRecord b) {
    final byLocation = locationScore(b).compareTo(locationScore(a));
    if (byLocation != 0) return byLocation;
    final byAge = a.modified.compareTo(b.modified);
    if (byAge != 0) return byAge;
    final byLength = a.path.length.compareTo(b.path.length);
    if (byLength != 0) return byLength;
    return a.path.compareTo(b.path);
  }

  FileRecord chooseKeep(List<FileRecord> members) =>
      (List.of(members)..sort(compare)).first;

  /// True if removing [removeIds] from [memberIds] leaves at least one copy.
  static bool keepsAtLeastOne(
    Iterable<int> memberIds,
    Set<int> removeIds,
  ) =>
      memberIds.any((id) => !removeIds.contains(id));
}
