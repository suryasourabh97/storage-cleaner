import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late World w;
  setUp(() => w = World());

  test('indexes files with category, protection and OneDrive flags', () {
    w.fs
      ..addFile(r'C:\Users\surya\Downloads\setup.exe', size: 10)
      ..addFile(r'C:\Users\surya\Documents\cv.pdf', size: 20)
      ..addFile(r'C:\Users\surya\Pictures\Camera Roll\a.jpg', size: 30)
      ..addFile(r'C:\Users\surya\OneDrive - Harbinger\plan.docx', size: 40)
      ..addFile(r'D:\Movies\film.mkv', size: 50);

    final s = w.scan();
    expect(s.status, RunStatus.complete);
    expect(s.files, 5);

    expect(w.db.byPath(r'C:\Users\surya\Downloads\setup.exe')!.category,
        Category.downloads);
    expect(w.db.byPath(r'C:\Users\surya\Documents\cv.pdf')!.category,
        Category.documents);
    final pic = w.db.byPath(r'C:\Users\surya\Pictures\Camera Roll\a.jpg')!;
    expect(pic.category, Category.pictures);
    expect(pic.isProtected, isTrue);
    expect(w.db.byPath(r'C:\Users\surya\OneDrive - Harbinger\plan.docx')!
        .cloudSynced, isTrue);
    final film = w.db.byPath(r'D:\Movies\film.mkv')!;
    expect(film.category, Category.videos);
    expect(film.volumeSerial, 2002);
  });

  test('never enters protected, hidden-system, dot, link or trash folders',
      () {
    w.fs
      ..addFile(r'C:\Users\surya\AppData\Local\app.db')
      ..addFile(r'C:\Windows\notepad.exe')
      ..addFile(r'C:\Users\surya\.gradle\caches\x.jar')
      ..addDir(r'D:\System Volume Information',
          attrs: const FileAttrs(hidden: true, system: true))
      ..addFile(r'D:\System Volume Information\x.dat')
      ..addDir(r'C:\Users\surya\Documents\Link',
          attrs: const FileAttrs(isLink: true))
      ..addFile(r'C:\Users\surya\Documents\Link\target.txt')
      ..addFile(r'C:\Users\surya\StorageCleaner Trash\Downloads\old.zip')
      ..addFile(r'D:\StorageCleaner Trash\old.iso')
      ..addFile(r'C:\Users\surya\Documents\keep.txt');

    w.scan();
    expect(w.db.countAll(), 1);
    expect(w.db.byPath(r'C:\Users\surya\Documents\keep.txt'), isNotNull);
  });

  test('records online-only files but never offers them', () {
    w.fs.addFile(r'C:\Users\surya\OneDrive - Harbinger\cloud.mp4',
        size: 900, attrs: const FileAttrs(onlineOnly: true),
        modified: DateTime.utc(2020));
    w.scan();
    expect(w.db.byPath(r'C:\Users\surya\OneDrive - Harbinger\cloud.mp4')!
        .onlineOnly, isTrue);
    expect(
        oldFiles(w.db, threshold: AgeThreshold.months6, now: w.clock.now()),
        isEmpty);
  });

  test('unreadable folders are counted and skipped', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\Secret\a.txt')
      ..addFile(r'C:\Users\surya\Documents\b.txt')
      ..deny(r'C:\Users\surya\Documents\Secret');
    final s = w.scan();
    expect(s.unreadableDirs, 1);
    expect(w.db.byPath(r'C:\Users\surya\Documents\b.txt'), isNotNull);
  });

  test('rescan forgets deleted files and picks up edits', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\a.txt', size: 1)
      ..addFile(r'C:\Users\surya\Documents\b.txt', size: 1);
    w.scan();
    w.fs
      ..externalDelete(r'C:\Users\surya\Documents\a.txt')
      ..modifyFile(r'C:\Users\surya\Documents\b.txt', size: 99);
    final s = w.scan();
    expect(s.forgotten, 1);
    expect(w.db.byPath(r'C:\Users\surya\Documents\a.txt'), isNull);
    expect(w.db.byPath(r'C:\Users\surya\Documents\b.txt')!.size, 99);
  });

  test('a cancelled scan keeps what it found and forgets nothing', () {
    w.fs.addFile(r'C:\Users\surya\Documents\a.txt');
    w.scan();
    w.fs.externalDelete(r'C:\Users\surya\Documents\a.txt');
    final s = w.scan(cancel: CancelToken()..cancel());
    expect(s.status, RunStatus.interrupted);
    expect(w.db.latestScanRun()!.status, RunStatus.interrupted);
    expect(w.db.byPath(r'C:\Users\surya\Documents\a.txt'), isNotNull,
        reason: 'only a complete walk may forget files');
  });

  test('a disconnected drive is skipped without forgetting its files', () {
    w.fs.addFile(r'D:\Movies\film.mkv');
    w.scan();
    w.fs.unmountVolume(r'D:\');
    final s = w.scan();
    expect(s.status, RunStatus.complete);
    expect(w.db.byPath(r'D:\Movies\film.mkv'), isNotNull);
  });

  test('user exclusions are not scanned', () {
    w.fs
      ..addFile(r'C:\Users\surya\Documents\Archive\a.txt')
      ..addFile(r'C:\Users\surya\Documents\b.txt');
    w.db.addExclusion(r'C:\Users\surya\Documents\Archive');
    w.scan();
    expect(w.db.byPath(r'C:\Users\surya\Documents\Archive\a.txt'), isNull);
    expect(w.db.byPath(r'C:\Users\surya\Documents\b.txt'), isNotNull);
  });
}
