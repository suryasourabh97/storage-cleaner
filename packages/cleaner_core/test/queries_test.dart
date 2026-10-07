import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late World w;
  setUp(() => w = World());

  DateTime daysAgo(int d) => w.clock.now().subtract(Duration(days: d));
  const mb = 1024 * 1024;

  group('old files', () {
    test('uses the age threshold on last-modified time', () {
      w.fs
        ..addFile(r'C:\Users\surya\Documents\old.txt', modified: daysAgo(200))
        ..addFile(r'C:\Users\surya\Documents\new.txt', modified: daysAgo(100));
      w.scan();
      final six = oldFiles(w.db,
          threshold: AgeThreshold.months6, now: w.clock.now());
      expect(six.map((c) => c.record.path),
          [r'C:\Users\surya\Documents\old.txt']);
      final three = oldFiles(w.db,
          threshold: AgeThreshold.months3, now: w.clock.now());
      expect(three, hasLength(2), reason: 'threshold change = re-query only');
    });

    test('pictures and always-keep files start unselected', () {
      w.fs
        ..addFile(r'C:\Users\surya\Pictures\a.jpg', modified: daysAgo(400))
        ..addFile(r'C:\Users\surya\OneDrive - Harbinger\pinned.pdf',
            modified: daysAgo(400), attrs: const FileAttrs(pinned: true))
        ..addFile(r'C:\Users\surya\Downloads\z.zip', modified: daysAgo(400));
      w.scan();
      final byPath = {
        for (final c in oldFiles(w.db,
            threshold: AgeThreshold.months6, now: w.clock.now()))
          c.record.path: c,
      };
      expect(byPath[r'C:\Users\surya\Pictures\a.jpg']!.preselected, isFalse);
      expect(
          byPath[r'C:\Users\surya\OneDrive - Harbinger\pinned.pdf']!
              .preselected,
          isFalse);
      expect(byPath[r'C:\Users\surya\Downloads\z.zip']!.preselected, isTrue);
    });

    test('OneDrive files are offered Free up space, others trash', () {
      w.fs
        ..addFile(r'C:\Users\surya\OneDrive - Harbinger\a.pdf',
            modified: daysAgo(400))
        ..addFile(r'C:\Users\surya\Documents\b.pdf', modified: daysAgo(400));
      w.scan();
      final actions = {
        for (final c in oldFiles(w.db,
            threshold: AgeThreshold.months6, now: w.clock.now()))
          c.record.path: c.action,
      };
      expect(actions[r'C:\Users\surya\OneDrive - Harbinger\a.pdf'],
          CandidateAction.freeUpSpace);
      expect(actions[r'C:\Users\surya\Documents\b.pdf'], CandidateAction.trash);
    });

    test('exclusions added after a scan hide existing results', () {
      w.fs.addFile(r'C:\Users\surya\Documents\Tax\2019.pdf',
          modified: daysAgo(900));
      w.scan();
      w.db.addExclusion(r'C:\Users\surya\Documents\Tax');
      expect(
          oldFiles(w.db, threshold: AgeThreshold.months6, now: w.clock.now()),
          isEmpty);
    });
  });

  group('large files', () {
    test('any age above the threshold, largest first', () {
      w.fs
        ..addFile(r'D:\VMs\win.vhdx', size: 4000 * mb, modified: daysAgo(30))
        ..addFile(r'C:\Users\surya\Videos\clip.mp4',
            size: 600 * mb, modified: daysAgo(30))
        ..addFile(r'C:\Users\surya\Documents\small.pdf', size: 5 * mb);
      w.scan();
      final large = largeFiles(w.db,
          threshold: SizeThreshold.defaultValue, now: w.clock.now());
      expect(large.map((c) => c.record.path),
          [r'D:\VMs\win.vhdx', r'C:\Users\surya\Videos\clip.mp4']);
      final huge =
          largeFiles(w.db, threshold: SizeThreshold.gb2, now: w.clock.now());
      expect(huge, hasLength(1));
    });

    test('files changed in the last 7 days start unselected', () {
      w.fs
        ..addFile(r'C:\Users\surya\Videos\recent.mp4',
            size: 900 * mb, modified: daysAgo(3))
        ..addFile(r'C:\Users\surya\Videos\older.mp4',
            size: 900 * mb, modified: daysAgo(30));
      w.scan();
      final sel = {
        for (final c in largeFiles(w.db,
            threshold: SizeThreshold.mb500, now: w.clock.now()))
          c.record.path: c.preselected,
      };
      expect(sel[r'C:\Users\surya\Videos\recent.mp4'], isFalse);
      expect(sel[r'C:\Users\surya\Videos\older.mp4'], isTrue);
    });
  });
}
