import '../index/index_db.dart';
import '../model/models.dart';
import '../model/path_key.dart';

/// A file offered for cleanup, with the default selection and action.
final class Candidate {
  const Candidate({
    required this.record,
    required this.preselected,
    required this.action,
  });

  final FileRecord record;
  final bool preselected;
  final CandidateAction action;
}

enum CandidateAction {
  /// Move to the app's trash.
  trash,

  /// OneDrive "Free up space" (file stays in the cloud).
  freeUpSpace,
}

/// Age thresholds offered in Settings (spec D7).
enum AgeThreshold {
  months3(Duration(days: 91)),
  months6(Duration(days: 182)),
  year1(Duration(days: 365)),
  years2(Duration(days: 730));

  const AgeThreshold(this.duration);
  final Duration duration;

  static const defaultValue = AgeThreshold.months6;
}

/// Size thresholds offered in Settings (spec D15).
enum SizeThreshold {
  mb100(100), mb250(250), mb500(500), gb1(1024), gb2(2048);

  const SizeThreshold(this.megabytes);
  final int megabytes;
  int get bytes => megabytes * 1024 * 1024;

  static const defaultValue = SizeThreshold.mb500;
}

CandidateAction _actionFor(FileRecord r) =>
    r.cloudSynced ? CandidateAction.freeUpSpace : CandidateAction.trash;

List<FileRecord> _withoutExcluded(List<FileRecord> rows, List<String> excl) =>
    excl.isEmpty
        ? rows
        : [
            for (final r in rows)
              if (!excl.any((e) => isWithinOrEqual(e, r.path))) r,
          ];

/// Files not modified within [threshold] (spec flow 3).
List<Candidate> oldFiles(
  IndexDb db, {
  required AgeThreshold threshold,
  required DateTime now,
}) {
  final rows = _withoutExcluded(
    db.indexedFiles(modifiedBefore: now.subtract(threshold.duration)),
    db.exclusions(),
  );
  return [
    for (final r in rows)
      Candidate(
        record: r,
        // Pictures and "always keep on this device" start unselected.
        preselected: !r.isProtected && !r.pinned,
        action: _actionFor(r),
      ),
  ];
}

/// Files at or above [threshold], any age (spec flow 9).
List<Candidate> largeFiles(
  IndexDb db, {
  required SizeThreshold threshold,
  required DateTime now,
}) {
  final recentCutoff = now.subtract(const Duration(days: 7));
  final rows = _withoutExcluded(
    db.indexedFiles(minSize: threshold.bytes),
    db.exclusions(),
  );
  return [
    for (final r in rows)
      Candidate(
        record: r,
        preselected: !r.modified.isAfter(recentCutoff) &&
            !r.isProtected &&
            !r.pinned,
        action: _actionFor(r),
      ),
  ];
}
