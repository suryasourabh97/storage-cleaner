import 'dart:convert';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late World w;
  setUp(() => w = World());

  const report = r'C:\Users\surya\Downloads\report.pdf';
  const trashedReport = r'C:\Users\surya\StorageCleaner Trash\Downloads\report.pdf';

  Map<String, Object?> manifestJson(String root) =>
      jsonDecode(utf8.decode(w.fs.readBytes('$root\\manifest.json')))
          as Map<String, Object?>;

  group('move to trash', () {
    test('renames into a mirrored folder on the same drive', () {
      w.addOldFile(report);
      w.scan();
      final res = w.trash.moveToTrash([w.idOf(report)]);

      expect(res.doneCount, 1);
      expect(w.fs.exists(report), isFalse);
      expect(w.fs.exists(trashedReport), isTrue);
      expect(w.fs.exists('$systemTrash\\README.txt'), isTrue);

      final row = w.db.byPath(trashedReport)!;
      expect(row.state, ItemState.trashed);
      expect(row.originalPath, report);
      expect(row.trashedAt, w.clock.now());

      final items = manifestJson(systemTrash)['items'] as List<Object?>;
      expect(items, hasLength(1));
      final item = items.single as Map<String, Object?>;
      expect(item['trashPath'], r'Downloads\report.pdf');
      expect(item['originalPath'], report);
    });

    test('files on another drive go to that drive\'s trash', () {
      w.addOldFile(r'D:\Photos\2019\x.jpg');
      w.scan();
      w.trash.moveToTrash([w.idOf(r'D:\Photos\2019\x.jpg')]);
      expect(w.fs.exists(r'D:\StorageCleaner Trash\Photos\2019\x.jpg'), isTrue);
      expect(w.fs.mutationLog.where((m) => m.contains(r'C:\')), isEmpty);
    });

    test('skips files changed since the scan', () {
      w.addOldFile(report);
      w.scan();
      w.fs.modifyFile(report, size: 5);
      final res = w.trash.moveToTrash([w.idOf(report)]);
      expect(res.skipped.single.reason, SkipReason.changedSinceScan);
      expect(w.fs.exists(report), isTrue);
      expect(w.db.byPath(report)!.state, ItemState.indexed);
    });

    test('skips and forgets files deleted since the scan', () {
      w.addOldFile(report);
      w.scan();
      final id = w.idOf(report);
      w.fs.externalDelete(report);
      final res = w.trash.moveToTrash([id]);
      expect(res.skipped.single.reason, SkipReason.notFound);
      expect(w.db.byId(id), isNull);
    });

    test('files in use stay put and stay indexed', () {
      w.addOldFile(report);
      w.scan();
      w.fs.lock(report);
      final res = w.trash.moveToTrash([w.idOf(report)]);
      expect(res.skipped.single.reason, SkipReason.inUse);
      expect(w.db.byPath(report)!.state, ItemState.indexed);
      expect(w.trash.manifestFor(systemTrash).items, isEmpty);
    });

    test('name collisions in the trash get a suffix', () {
      w.addOldFile(report);
      w.scan();
      w.trash.moveToTrash([w.idOf(report)]);
      w.addOldFile(report);
      w.scan();
      w.trash.moveToTrash([w.idOf(report)]);
      expect(w.fs.exists(trashedReport), isTrue);
      expect(
          w.fs.exists(
              r'C:\Users\surya\StorageCleaner Trash\Downloads\report (1).pdf'),
          isTrue);
      expect(manifestJson(systemTrash)['items'], hasLength(2));
    });
  });

  group('restore', () {
    late int id;
    setUp(() {
      w.addOldFile(report);
      w.scan();
      id = w.idOf(report);
      w.trash.moveToTrash([id]);
    });

    test('puts the file back and drops it from the manifest', () {
      final r = w.trash.restore(id);
      expect(r, isA<Restored>());
      expect(w.fs.exists(report), isTrue);
      expect(w.fs.exists(trashedReport), isFalse);
      expect(w.db.byId(id)!.state, ItemState.indexed);
      expect(w.db.byId(id)!.path, report);
      expect(manifestJson(systemTrash)['items'], isEmpty);
    });

    test('recreates the original folder if it is gone', () {
      w.fs.externalDelete(downloads);
      expect(w.trash.restore(id), isA<Restored>());
      expect(w.fs.exists(report), isTrue);
    });

    test('asks when the original location is taken', () {
      w.fs.addFile(report, size: 7);
      expect(w.trash.restore(id), isA<RestoreConflict>());
      expect(w.fs.exists(trashedReport), isTrue);

      final r = w.trash.restore(id, choice: const KeepBoth());
      expect((r as Restored).path, r'C:\Users\surya\Downloads\report (1).pdf');
      expect(w.fs.readBytes(report), hasLength(7),
          reason: 'existing file untouched');
    });

    test('can restore into another folder', () {
      final r = w.trash.restore(id, choice: const RestoreInto(documents));
      expect((r as Restored).path, r'C:\Users\surya\Documents\report.pdf');
    });

    test('a file on a disconnected drive cannot be restored yet', () {
      w.addOldFile(r'D:\a.iso');
      w.scan();
      final d = w.idOf(r'D:\a.iso');
      w.trash.moveToTrash([d]);
      w.fs.unmountVolume(r'D:\');
      final r = w.trash.restore(d);
      expect((r as RestoreFailed).reason, SkipReason.volumeUnavailable);
      expect(w.db.byId(d)!.state, ItemState.trashed);
    });
  });

  group('permanent delete', () {
    late int id;
    setUp(() {
      w.addOldFile(report);
      w.scan();
      id = w.idOf(report);
      w.trash.moveToTrash([id]);
    });

    test('requires the user\'s confirmation', () {
      final res = w.trash
          .deletePermanently([id], DeletionConfirmation.userConfirmed(const []));
      expect(res.skipped.single.reason, SkipReason.notConfirmed);
      expect(w.fs.exists(trashedReport), isTrue);
      expect(w.db.byId(id)!.state, ItemState.trashed);
    });

    test('deletes confirmed items and forgets them', () {
      final res = w.trash.deletePermanently(
          [id], DeletionConfirmation.userConfirmed([trashedReport]));
      expect(res.doneCount, 1);
      expect(w.fs.exists(trashedReport), isFalse);
      expect(w.db.byId(id), isNull);
      expect(manifestJson(systemTrash)['items'], isEmpty);
    });

    test('only trashed items can be permanently deleted', () {
      w.fs.addFile(r'C:\Users\surya\Documents\live.txt');
      w.scan();
      final live = w.idOf(r'C:\Users\surya\Documents\live.txt');
      final res = w.trash.deletePermanently([live],
          DeletionConfirmation.userConfirmed([r'C:\Users\surya\Documents\live.txt']));
      expect(res.skipped.single.reason, SkipReason.wrongState);
      expect(w.fs.exists(r'C:\Users\surya\Documents\live.txt'), isTrue);
    });
  });
}
