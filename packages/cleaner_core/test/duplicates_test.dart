@Tags(['safety'])
library;

import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late World w;
  setUp(() => w = World());

  const mb = 1024 * 1024;
  List<int> content(int seed, int size) =>
      List.generate(size, (i) => (i * 31 + seed) & 0xFF);

  DuplicateFinder finder() =>
      DuplicateFinder(fs: w.fs, db: w.db, clock: w.clock);

  AnalysisSummary analyze({int minSize = 1, CancelToken? cancel}) =>
      finder().run(minSize: minSize, cancel: cancel);

  List<DuplicateGroup> groups({int minSize = 1}) => duplicateGroups(
        w.db,
        minSize: minSize,
        rules: KeepRules(w.categorizer.folders),
      );

  DateTime yearsAgo(int y) =>
      w.clock.now().subtract(Duration(days: 365 * y));

  test('identical content is grouped, whatever the names', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\report.pdf',
          bytes: content(1, 300000))
      ..addFile(r'C:\Users\surya\Downloads\report (1).pdf',
          bytes: content(1, 300000))
      ..addFile(r'D:\Backup\copy-of-report.pdf', bytes: content(1, 300000));
    w.scan();
    final s = analyze();
    expect(s.status, RunStatus.complete);
    expect(s.groups, 1);
    final g = groups().single;
    expect(g.members, hasLength(3));
    expect(g.reclaimable, 2 * 300000);
  });

  test('same size but different content is not a duplicate', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\a.bin', bytes: content(1, 5000))
      ..addFile(r'C:\Users\surya\Documents\b.bin', bytes: content(2, 5000));
    w.scan();
    analyze();
    expect(groups(), isEmpty);
  });

  test('files that differ only in the middle are told apart by full hash', () {
    final a = content(1, 400000);
    final b = List<int>.of(a)..[200000 + 70000] ^= 0xFF; // outside samples
    w.fs
      ..addFile(r'C:\Users\surya\Documents\a.bin', bytes: a)
      ..addFile(r'C:\Users\surya\Documents\b.bin', bytes: b);
    w.scan();
    analyze();
    expect(groups(), isEmpty);
  });

  test('hard links are never reported as duplicates', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\a.bin', bytes: content(1, 5000))
      ..addHardLink(r'C:\Users\surya\Documents\a.bin',
          r'C:\Users\surya\Desktop\a-link.bin');
    w.scan();
    analyze();
    expect(groups(), isEmpty);
  });

  test('online-only OneDrive files are never read', () {
    w.fs
      ..addFile(r'C:\Users\surya\OneDrive - Harbinger\cloud.bin',
          size: 5000, attrs: const FileAttrs(onlineOnly: true))
      ..addFile(r'C:\Users\surya\Documents\local.bin', size: 5000);
    w.scan();
    analyze();
    expect(
      w.fs.contentReads.where((p) => p.contains('OneDrive')),
      isEmpty,
    );
  });

  test('image files are compared even below the general minimum', () {
    w.fs
      ..addFile(r'C:\Users\surya\Pictures\Screenshots\shot.png',
          bytes: content(4, 60000))
      ..addFile(r'C:\Users\surya\Downloads\shot (1).png',
          bytes: content(4, 60000))
      ..addFile(r'C:\Users\surya\Documents\a.txt', bytes: content(5, 60000))
      ..addFile(r'C:\Users\surya\Documents\b.txt', bytes: content(5, 60000));
    w.scan();
    analyze(minSize: 1 * mb);
    final g = groups(minSize: mb);
    expect(g, hasLength(1), reason: 'the two text files stay below 1 MB');
    expect(g.single.members.map((m) => winPath.extension(m.path)).toSet(),
        {'.png'});
  });

  test('files below the minimum size are ignored', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\a.txt', bytes: content(1, 100))
      ..addFile(r'C:\Users\surya\Documents\b.txt', bytes: content(1, 100));
    w.scan();
    analyze(minSize: 1 * mb);
    expect(w.fs.contentReads, isEmpty);
    expect(groups(minSize: mb), isEmpty);
  });

  test('a repeat run on an unchanged disk reads nothing', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\a.bin', bytes: content(1, 9000))
      ..addFile(r'C:\Users\surya\Documents\b.bin', bytes: content(1, 9000));
    w.scan();
    analyze();
    final before = w.fs.bytesRead;
    w.scan();
    final again = analyze();
    expect(w.fs.bytesRead, before);
    expect(again.groups, 1);
  });

  test('an edited file is re-hashed on the next scan', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\a.bin', bytes: content(1, 9000))
      ..addFile(r'C:\Users\surya\Documents\b.bin', bytes: content(1, 9000));
    w.scan();
    analyze();
    expect(groups(), hasLength(1));
    w.clock.advance(const Duration(minutes: 5));
    w.fs.externalDelete(r'C:\Users\surya\Documents\b.bin');
    w.fs.addFile(r'C:\Users\surya\Documents\b.bin', bytes: content(9, 9000));
    w.scan();
    analyze();
    expect(groups(), isEmpty);
  });

  test('a cancelled run keeps its progress and the next run finishes', () {
    for (var i = 0; i < 4; i++) {
      w.fs.addFile('C:\\Users\\surya\\Documents\\f$i.bin',
          bytes: content(1, 9000));
    }
    w.scan();
    final first = analyze(cancel: CancelToken()..cancel());
    expect(first.status, RunStatus.interrupted);
    expect(w.db.latestAnalysis('duplicates')!.$2, RunStatus.interrupted);
    final second = analyze();
    expect(second.status, RunStatus.complete);
    expect(groups().single.members, hasLength(4));
  });

  group('keep rules', () {
    test('prefer OneDrive, then Documents over Downloads, then oldest', () {
      w.fs
        ..addFile(r'C:\Users\surya\Downloads\a.bin',
            bytes: content(1, 5000), modified: yearsAgo(5))
        ..addFile(r'C:\Users\surya\Documents\a.bin',
            bytes: content(1, 5000), modified: yearsAgo(1))
        ..addFile(r'C:\Users\surya\OneDrive - Harbinger\a.bin',
            bytes: content(1, 5000), modified: yearsAgo(1));
      w.scan();
      analyze();
      expect(groups().single.suggestedKeep.path,
          r'C:\Users\surya\OneDrive - Harbinger\a.bin');

      w.fs.externalDelete(r'C:\Users\surya\OneDrive - Harbinger\a.bin');
      w.scan();
      analyze();
      expect(groups().single.suggestedKeep.path,
          r'C:\Users\surya\Documents\a.bin');
    });

    test('oldest wins among equally good locations', () {
      w.fs
        ..addFile(r'D:\Photos\x.jpg', bytes: content(1, 5000),
            modified: yearsAgo(1))
        ..addFile(r'D:\Archive\x.jpg', bytes: content(1, 5000),
            modified: yearsAgo(3));
      w.scan();
      analyze();
      expect(groups().single.suggestedKeep.path, r'D:\Archive\x.jpg');
    });
  });

  group('removal', () {
    late DuplicateGroup g;
    setUp(() {
      w.fs
        ..addFile(r'C:\Users\surya\Documents\a.bin',
            bytes: content(1, 5000), modified: yearsAgo(2))
        ..addFile(r'C:\Users\surya\Downloads\a.bin', bytes: content(1, 5000))
        ..addFile(r'C:\Users\surya\Desktop\a (2).bin', bytes: content(1, 5000));
      w.scan();
      analyze();
      g = groups().single;
    });

    Set<int> extras() =>
        {for (final m in g.members) if (m.id != g.suggestedKeep.id) m.id};

    BatchResult remove(int keepId, Set<int> ids) => removeDuplicates(
          [DuplicateRemoval(group: g, keepId: keepId, removeIds: ids)],
          db: w.db,
          fs: w.fs,
          trash: w.trash,
        );

    test('extra copies go to the trash and the kept copy stays', () {
      final r = remove(g.suggestedKeep.id, extras());
      expect(r.doneCount, 2);
      expect(w.fs.exists(g.suggestedKeep.path), isTrue);
      expect(w.db.inState(ItemState.trashed), hasLength(2));
    });

    test('a selection that removes every copy is refused', () {
      final all = {for (final m in g.members) m.id};
      final r = remove(g.suggestedKeep.id, all);
      expect(r.doneCount, 0);
      for (final m in g.members) {
        expect(w.fs.exists(m.path), isTrue);
      }
      expect(KeepRules.keepsAtLeastOne(all, all), isFalse);
    });

    test('if the kept copy disappeared, nothing in the group is removed', () {
      w.fs.externalDelete(g.suggestedKeep.path);
      final r = remove(g.suggestedKeep.id, extras());
      expect(r.doneCount, 0);
      expect(r.skipped.map((s) => s.reason).toSet(),
          {SkipReason.keptCopyChanged});
      for (final m in g.members.where((m) => m.id != g.suggestedKeep.id)) {
        expect(w.fs.exists(m.path), isTrue);
      }
    });

    test('if the kept copy was edited, nothing in the group is removed', () {
      w.fs.modifyFile(g.suggestedKeep.path, size: 5001);
      final r = remove(g.suggestedKeep.id, extras());
      expect(r.doneCount, 0);
      expect(r.skippedCount, 2);
    });

    test('a removed copy that changed since analysis is skipped', () {
      final victim =
          g.members.firstWhere((m) => m.id != g.suggestedKeep.id);
      w.fs.modifyFile(victim.path, size: 4999);
      final r = remove(g.suggestedKeep.id, extras());
      expect(r.doneCount, 1);
      expect(w.fs.exists(victim.path), isTrue);
    });
  });
}
