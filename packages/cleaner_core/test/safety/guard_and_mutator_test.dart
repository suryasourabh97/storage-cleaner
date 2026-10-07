@Tags(['safety'])
library;

import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import '../support.dart';

void main() {
  late World w;
  setUp(() => w = World());

  group('PathGuard', () {
    test('allows ordinary user files', () {
      w.fs.addFile(r'C:\Users\surya\Downloads\a.pdf');
      expect(w.guard.allows(r'C:\Users\surya\Downloads\a.pdf'), isTrue);
    });

    test('rejects paths outside allowed roots', () {
      expect(w.guard.allows(r'C:\Temp\a.txt'), isFalse);
      expect(w.guard.allows(r'C:\Users\suryaX\a.txt'), isFalse);
      expect(w.guard.allows(r'C:\Users\surya'), isFalse,
          reason: 'a root itself is never a target');
    });

    test('rejects protected locations', () {
      expect(w.guard.allows(r'C:\Users\surya\AppData\Local\x.db'), isFalse);
      expect(w.guard.allows(r'C:\Windows\System32\x.dll'), isFalse);
      expect(w.guard.allows(r'D:\Program Files\App\a.exe'), isFalse);
      expect(w.guard.allows(r'D:\$Recycle.Bin\x'), isFalse);
    });

    test('allows explicit exceptions inside protected roots', () {
      final guard = PathGuard(
        w.fs,
        GuardConfig(
          allowedRoots: [profile],
          protectedRoots: [r'C:\Users\surya\AppData'],
          protectedExceptions: [r'C:\Users\surya\AppData\Local\App\Cache'],
        ),
      );
      expect(guard.allows(r'C:\Users\surya\AppData\Local\App\Cache\f_001'),
          isTrue);
      expect(guard.allows(r'C:\Users\surya\AppData\Local\App\Cookies'),
          isFalse);
    });

    test('rejects anything reached through a junction or symlink', () {
      // A junction inside Documents that points at a protected folder.
      w.fs
        ..addDir(r'C:\Users\surya\Documents\Shortcut',
            attrs: const FileAttrs(isLink: true))
        ..addFile(r'C:\Users\surya\Documents\Shortcut\important.db');
      expect(
          w.guard.allows(r'C:\Users\surya\Documents\Shortcut\important.db'),
          isFalse);
    });
  });

  group('FileMutator', () {
    const file = r'C:\Users\surya\Downloads\a.pdf';

    test('permanent delete without confirmation does nothing', () {
      w.fs.addFile(file);
      final out = w.mutator.deletePermanently(
          file, DeletionConfirmation.userConfirmed(const []));
      expect(out, isA<OpSkipped>());
      expect((out as OpSkipped).reason, SkipReason.notConfirmed);
      expect(w.fs.exists(file), isTrue);
      expect(w.fs.mutationLog, isEmpty);
    });

    test('a confirmation covers only its own paths, once each', () {
      w.fs
        ..addFile(file)
        ..addFile(r'C:\Users\surya\Downloads\b.pdf');
      final c = DeletionConfirmation.userConfirmed([file]);
      expect(w.mutator.deletePermanently(r'C:\Users\surya\Downloads\b.pdf', c),
          isA<OpSkipped>());
      expect(w.mutator.deletePermanently(file, c), isA<OpDone>());
      w.fs.addFile(file);
      expect(w.mutator.deletePermanently(file, c), isA<OpSkipped>(),
          reason: 'confirmation is single-use');
      expect(w.fs.exists(file), isTrue);
    });

    test('never copies across drives', () {
      w.fs.addFile(file);
      final out = w.mutator.move(file, r'D:\elsewhere\a.pdf');
      expect((out as OpSkipped).reason, SkipReason.crossVolume);
      expect(w.fs.exists(file), isTrue);
      expect(w.fs.exists(r'D:\elsewhere\a.pdf'), isFalse);
    });

    test('never overwrites an existing target', () {
      w.fs
        ..addFile(file)
        ..addFile(r'C:\Users\surya\Documents\a.pdf');
      final out = w.mutator.move(file, r'C:\Users\surya\Documents\a.pdf');
      expect((out as OpSkipped).reason, SkipReason.alreadyExists);
    });

    test('reports files in use', () {
      w.fs
        ..addFile(file)
        ..lock(file);
      final out = w.mutator.move(file, r'C:\Users\surya\Documents\a.pdf');
      expect((out as OpSkipped).reason, SkipReason.inUse);
      expect(w.fs.exists(file), isTrue);
    });

    test('refuses protected targets', () {
      w.fs.addFile(file);
      final out = w.mutator.move(file, r'C:\Users\surya\AppData\Local\a.pdf');
      expect((out as OpSkipped).reason, SkipReason.guardRejected);
    });
  });
}
