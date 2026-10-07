@Tags(['safety'])
library;

import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late World w;
  setUp(() => w = World());

  int trashed(String path) {
    w.addOldFile(path, size: 100);
    w.scan();
    final id = w.idOf(path);
    w.trash.moveToTrash([id]);
    return id;
  }

  test('items become ready after 30 days', () {
    final id = trashed(r'C:\Users\surya\Downloads\a.pdf');
    w.clock.advance(const Duration(days: 10));
    expect(w.purge.check().isEmpty, isTrue);
    expect(w.purge.trashItems().single.daysLeft, 20);

    w.clock.advance(const Duration(days: 21));
    final s = w.purge.check();
    expect(s.ids, [id]);
    expect(s.bytes, 100);
  });

  test('items on a disconnected drive are never offered', () {
    trashed(r'D:\Old\c.iso');
    w.clock.advance(const Duration(days: 40));
    w.fs.unmountVolume(r'D:\');
    expect(w.purge.check().isEmpty, isTrue);
    expect(w.purge.trashItems().single.available, isFalse);
  });

  test('the check never changes anything on disk', () {
    trashed(r'C:\Users\surya\Downloads\a.pdf');
    w.clock.advance(const Duration(days: 60));
    final before = List<String>.of(w.fs.mutationLog);
    w.purge.check();
    w.purge.trashItems();
    expect(w.fs.mutationLog, before);
    expect(w.db.inState(ItemState.trashed), hasLength(1));
  });
}
