@TestOn('windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage_cleaner/platform/windows/system_info.dart';
import 'package:storage_cleaner/platform/windows/windows_fs.dart';
import 'package:win32/win32.dart';

/// These run against the real Windows file system on the CI runner.
void main() {
  late Directory tmp;
  late String root;
  final fs = WindowsPlatformFs();

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('sc_test_');
    root = tmp.resolveSymbolicLinksSync();
  });

  tearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // best effort
    }
  });

  String p(String rel) => '$root\\$rel';

  void write(String rel, {int size = 10}) {
    File(p(rel))
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(List.filled(size, 7));
  }

  test('volume serial is available for the temp drive', () {
    expect(fs.volumeSerialOf(root), isNotNull);
  });

  test('list and stat report name, size, date and directories', () {
    write('a.txt', size: 1234);
    Directory(p('sub')).createSync();
    final entries = {for (final e in fs.list(root)) winPath.basename(e.path): e};
    expect(entries.keys, containsAll(['a.txt', 'sub']));
    expect(entries['a.txt']!.size, 1234);
    expect(entries['a.txt']!.isDirectory, isFalse);
    expect(entries['sub']!.isDirectory, isTrue);
    final age = DateTime.now().toUtc().difference(entries['a.txt']!.modified);
    expect(age.inMinutes.abs(), lessThan(5));

    final s = fs.stat(p('a.txt'))!;
    expect(s.size, 1234);
    expect(fs.stat(p('missing.txt')), isNull);
    expect(fs.list(p('sub')), isEmpty);
  });

  test('hidden and system attributes are detected', () {
    write('h.txt');
    final path = p('h.txt').toNativeUtf16();
    try {
      SetFileAttributes(path, 0x2 | 0x4); // hidden | system
    } finally {
      free(path);
    }
    final e = fs.stat(p('h.txt'))!;
    expect(e.attrs.hidden, isTrue);
    expect(e.attrs.system, isTrue);
  });

  test('junctions are reported as links; plain folders are not', () {
    Directory(p('target')).createSync();
    final r = Process.runSync(
      'cmd',
      ['/c', 'mklink', '/J', p('junction'), p('target')],
    );
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final entries = {for (final e in fs.list(root)) winPath.basename(e.path): e};
    expect(entries['junction']!.attrs.isLink, isTrue);
    expect(entries['target']!.attrs.isLink, isFalse);
  });

  test('move renames; refuses to overwrite; replaceFile replaces', () {
    write('m.txt', size: 3);
    fs.move(p('m.txt'), p('n.txt'));
    expect(File(p('m.txt')).existsSync(), isFalse);
    expect(File(p('n.txt')).lengthSync(), 3);

    write('o.txt', size: 5);
    expect(
      () => fs.move(p('o.txt'), p('n.txt')),
      throwsA(isA<FsException>().having(
        (e) => e.code,
        'code',
        FsErrorCode.alreadyExists,
      )),
    );

    fs.replaceFile(p('o.txt'), p('n.txt'));
    expect(File(p('n.txt')).lengthSync(), 5);
    expect(File(p('o.txt')).existsSync(), isFalse);
  });

  test('delete removes a file; missing files report notFound', () {
    write('d.txt');
    fs.delete(p('d.txt'));
    expect(File(p('d.txt')).existsSync(), isFalse);
    expect(
      () => fs.delete(p('d.txt')),
      throwsA(isA<FsException>()
          .having((e) => e.code, 'code', FsErrorCode.notFound)),
    );
  });

  test('long paths beyond 260 characters work', () {
    final deep = List.filled(12, 'a_fairly_long_folder_name').join('\\');
    write('$deep\\file.txt', size: 4);
    expect(p('$deep\\file.txt').length, greaterThan(260));
    expect(fs.stat(p('$deep\\file.txt'))!.size, 4);
    fs.move(p('$deep\\file.txt'), p('$deep\\renamed.txt'));
    expect(fs.stat(p('$deep\\renamed.txt')), isNotNull);
  });

  test('full cycle on disk: scan, trash, manifest, restore', () {
    write('Downloads\\old.zip', size: 2048);
    write('Documents\\keep.txt', size: 1);
    // Make old.zip two years old.
    File(p('Downloads\\old.zip')).setLastModifiedSync(
      DateTime.now().subtract(const Duration(days: 730)),
    );

    final dbFile = p('index.db');
    final db = IndexDb.open(dbFile);
    addTearDown(db.close);
    final guard = PathGuard(fs, GuardConfig(allowedRoots: [root]));
    final mutator = FileMutator(fs, guard);
    final categorizer = Categorizer(KnownFolders(
      userProfile: root,
      downloads: p('Downloads'),
      documents: p('Documents'),
    ));
    const clock = SystemClock();
    final locator = TrashLocator(userProfile: root);
    final trash = TrashManager(
      fs: fs,
      db: db,
      mutator: mutator,
      locator: locator,
      clock: clock,
    );

    final summary = Scanner(
      fs: fs,
      db: db,
      categorizer: categorizer,
      clock: clock,
    ).run(ScanRequest(
      roots: [root],
      trashRoots: [locator.trashRootFor(root)],
    ));
    expect(summary.status, RunStatus.complete);

    final old = oldFiles(db, threshold: AgeThreshold.months6, now: clock.now());
    expect(old.map((c) => winPath.basename(c.record.path)), ['old.zip']);
    expect(old.single.record.category, Category.downloads);

    final res = trash.moveToTrash([old.single.record.id]);
    expect(res.doneCount, 1, reason: res.skipped.join(', '));
    final trashed = p('StorageCleaner Trash\\Downloads\\old.zip');
    expect(File(trashed).existsSync(), isTrue);
    expect(File(p('Downloads\\old.zip')).existsSync(), isFalse);

    final manifest = jsonDecode(
      File(p('StorageCleaner Trash\\manifest.json')).readAsStringSync(),
    ) as Map<String, Object?>;
    expect(manifest['items'], hasLength(1));
    expect(File(p('StorageCleaner Trash\\README.txt')).existsSync(), isTrue);

    final restored = trash.restore(old.single.record.id);
    expect(restored, isA<Restored>());
    expect(File(p('Downloads\\old.zip')).lengthSync(), 2048);
  });

  test('drive listing includes the system drive', () {
    final drives = listDrives();
    final system = Platform.environment['SystemDrive'] ?? 'C:';
    expect(
      drives.map((d) => d.root.toUpperCase()),
      contains('${system.toUpperCase()}\\'),
    );
  });

  test('known folders resolve to existing paths', () {
    final k = resolveKnownFolders();
    expect(Directory(k.userProfile).existsSync(), isTrue);
    expect(k.documents, isNotNull);
  });
}
