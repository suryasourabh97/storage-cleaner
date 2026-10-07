import '../index/index_db.dart';
import '../model/models.dart';
import '../platform/platform_fs.dart';

/// How long items stay in trash before they are offered for deletion.
const trashRetention = Duration(days: 30);

/// A trashed item as the Trash screen shows it.
final class TrashItem {
  const TrashItem({
    required this.record,
    required this.available,
    required this.daysLeft,
  });

  final FileRecord record;

  /// False if its drive is not connected.
  final bool available;

  /// Days until it is offered for permanent deletion (0 = ready now).
  final int daysLeft;

  bool get purgeReady => available && daysLeft == 0;
}

final class PurgeSummary {
  const PurgeSummary(this.items);
  final List<TrashItem> items;

  int get count => items.length;
  int get bytes => items.fold(0, (sum, i) => sum + i.record.size);
  List<int> get ids => [for (final i in items) i.record.id];
  bool get isEmpty => items.isEmpty;
}

/// Read-only view of the trash; used by the Trash screen, the on-launch
/// check and the daily scheduled check (ADR-005). Never deletes anything.
final class PurgeChecker {
  PurgeChecker({
    required IndexDb db,
    required PlatformFs fs,
    required Clock clock,
    this.retention = trashRetention,
  })  : _db = db,
        _fs = fs,
        _clock = clock;

  final IndexDb _db;
  final PlatformFs _fs;
  final Clock _clock;
  final Duration retention;

  List<TrashItem> trashItems() {
    final now = _clock.now();
    return [
      for (final r in _db.inState(ItemState.trashed))
        TrashItem(
          record: r,
          available: _fs.volumeSerialOf(r.path) != null,
          daysLeft: _daysLeft(r, now),
        ),
    ];
  }

  /// Items past the retention period on connected drives. Items on a
  /// disconnected drive are never offered.
  PurgeSummary check() =>
      PurgeSummary([for (final i in trashItems()) if (i.purgeReady) i]);

  int _daysLeft(FileRecord r, DateTime now) {
    final at = r.trashedAt;
    if (at == null) return 0;
    final due = at.add(retention);
    if (!due.isAfter(now)) return 0;
    return (due.difference(now).inHours / 24).ceil();
  }
}
