@Tags(['safety'])
library;

import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// Failure drills (spec §13.4): crashes at every step, index loss, and
/// uninstall/reinstall must never lose a file.
void main() {
  late World w;
  setUp(() => w = World());

  const a = r'C:\Users\surya\Downloads\a.pdf';
  const aTrash = r'C:\Users\surya\StorageCleaner Trash\Downloads\a.pdf';

  int indexed(String path) {
    w.addOldFile(path);
    w.scan();
    return w.idOf(path);
  }

  test('crash after the rename but before bookkeeping: move is completed',
      () {
    final id = indexed(a);
    w.db.markMoving(id, aTrash);
    w.fs.externalMove(a, aTrash); // the rename happened, then the crash

    final r = w.reconciler.run(trashRoots: w.trashRoots);
    expect(r.movesCompleted, 1);
    final row = w.db.byId(id)!;
    expect(row.state, ItemState.trashed);
    expect(row.path, aTrash);
    expect(w.trash.manifestFor(systemTrash).contains(aTrash), isTrue);
  });

  test('crash before the rename: move is reverted', () {
    final id = indexed(a);
    w.db.markMoving(id, aTrash);

    final r = w.reconciler.run(trashRoots: w.trashRoots);
    expect(r.movesReverted, 1);
    expect(w.db.byId(id)!.state, ItemState.indexed);
    expect(w.fs.exists(a), isTrue);
  });

  test('crash mid-restore: finished if the file moved, reverted if not', () {
    final id = indexed(a);
    w.trash.moveToTrash([id]);
    w.db.markRestoring(id, a);
    w.fs.externalMove(aTrash, a);
    w.reconciler.run(trashRoots: w.trashRoots);
    expect(w.db.byId(id)!.state, ItemState.indexed);
    expect(w.trash.manifestFor(systemTrash).contains(aTrash), isFalse);

    const b = r'C:\Users\surya\Downloads\b.pdf';
    const bTrash = r'C:\Users\surya\StorageCleaner Trash\Downloads\b.pdf';
    final idB = indexed(b);
    w.trash.moveToTrash([idB]);
    w.db.markRestoring(idB, b);
    w.reconciler.run(trashRoots: w.trashRoots);
    expect(w.db.byId(idB)!.state, ItemState.trashed);
    expect(w.fs.exists(bTrash), isTrue);
  });

  test('crash mid-delete with the file still present needs a new confirmation',
      () {
    final id = indexed(a);
    w.trash.moveToTrash([id]);
    w.db.markDeleting(id);
    final r = w.reconciler.run(trashRoots: w.trashRoots);
    expect(r.deletesReverted, 1);
    expect(w.db.byId(id)!.state, ItemState.trashed);
    expect(w.fs.exists(aTrash), isTrue);
  });

  test('index lost (app data cleared): trash is rebuilt from manifests', () {
    final ids = [
      indexed(a),
      indexed(r'C:\Users\surya\Documents\b.docx'),
      indexed(r'D:\Old\c.iso'),
    ];
    w.trash.moveToTrash(ids);

    w.loseIndex();
    final r = w.reconciler.run(trashRoots: w.trashRoots);

    expect(r.rebuilt, 3);
    final rows = w.db.inState(ItemState.trashed);
    expect(rows.map((x) => x.originalPath), unorderedEquals([
      a,
      r'C:\Users\surya\Documents\b.docx',
      r'D:\Old\c.iso',
    ]));
  });

  test('uninstall and reinstall: every trashed file is present and restorable',
      () {
    final files = [
      a,
      r'C:\Users\surya\Documents\Projects\plan.xlsx',
      r'D:\Backups\2018.zip',
    ];
    final ids = [for (final f in files) indexed(f)];
    w.trash.moveToTrash(ids);

    // Uninstall: app data gone; trash folders stay on disk.
    w.loseIndex();
    // Reinstall: launch-time reconciliation, then restore everything.
    w.reconciler.run(trashRoots: w.trashRoots);
    for (final row in w.db.inState(ItemState.trashed)) {
      expect(w.trash.restore(row.id), isA<Restored>());
    }
    for (final f in files) {
      expect(w.fs.exists(f), isTrue, reason: f);
    }
    expect(w.db.inState(ItemState.trashed), isEmpty);
  });

  test('manifest deleted by hand is rebuilt from the index', () {
    final id = indexed(a);
    w.trash.moveToTrash([id]);
    w.fs.externalDelete('$systemTrash\\manifest.json');
    w.loseIndexKeepingDb();
    final r = w.reconciler.run(trashRoots: w.trashRoots);
    expect(r.manifestRepaired, 1);
    expect(w.fs.exists('$systemTrash\\manifest.json'), isTrue);
  });

  test('a file removed from the trash by hand is forgotten', () {
    final id = indexed(a);
    w.trash.moveToTrash([id]);
    w.fs.externalDelete(aTrash);
    final r = w.reconciler.run(trashRoots: w.trashRoots);
    expect(r.vanished, 1);
    expect(w.db.byId(id), isNull);
  });

  test('items on a disconnected drive are left alone', () {
    final id = indexed(r'D:\Old\c.iso');
    w.trash.moveToTrash([id]);
    w.fs.unmountVolume(r'D:\');
    w.reconciler.run(trashRoots: w.trashRoots);
    expect(w.db.byId(id)!.state, ItemState.trashed);
  });
}

extension on World {
  /// Drops only the cached manifests (as after an app restart).
  void loseIndexKeepingDb() {
    trash = TrashManager(
      fs: fs,
      db: db,
      mutator: mutator,
      locator: locator,
      clock: clock,
    );
  }
}
