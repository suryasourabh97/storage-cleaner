import 'package:cleaner_core/cleaner_core.dart';

import 'fakes/memory_platform_fs.dart';

export 'fakes/memory_platform_fs.dart';

const profile = r'C:\Users\surya';
const downloads = r'C:\Users\surya\Downloads';
const documents = r'C:\Users\surya\Documents';
const pictures = r'C:\Users\surya\Pictures';
const oneDrive = r'C:\Users\surya\OneDrive - Harbinger';
const dataDrive = r'D:\';
const systemTrash = r'C:\Users\surya\StorageCleaner Trash';
const dataTrash = r'D:\StorageCleaner Trash';

/// A complete engine wired to an in-memory C: and D: drive.
final class World {
  World._(this.clock, this.fs, this.db, this.guard, this.mutator,
      this.categorizer, this.locator, this.trash);

  factory World() {
    final clock = FakeClock();
    final fs = MemoryPlatformFs(clock: clock)
      ..addVolume(r'C:\', 1001)
      ..addVolume(r'D:\', 2002)
      ..addDir(r'C:\Windows')
      ..addDir(downloads)
      ..addDir(documents)
      ..addDir(pictures)
      ..addDir(r'C:\Users\surya\AppData\Local');
    final db = IndexDb.inMemory();
    final guard = PathGuard(
      fs,
      GuardConfig(
        allowedRoots: [profile, dataDrive],
        protectedRoots: defaultProtectedRoots(
          windowsDir: r'C:\Windows',
          userProfile: profile,
          driveRoots: [r'C:\', r'D:\'],
        ),
      ),
    );
    final mutator = FileMutator(fs, guard);
    const categorizer = Categorizer(KnownFolders(
      userProfile: profile,
      downloads: downloads,
      documents: documents,
      pictures: pictures,
      oneDriveRoots: [oneDrive],
    ));
    final locator = TrashLocator(userProfile: profile);
    final trash = TrashManager(
      fs: fs,
      db: db,
      mutator: mutator,
      locator: locator,
      clock: clock,
    );
    return World._(
        clock, fs, db, guard, mutator, categorizer, locator, trash);
  }

  final FakeClock clock;
  final MemoryPlatformFs fs;
  IndexDb db;
  final PathGuard guard;
  final FileMutator mutator;
  final Categorizer categorizer;
  final TrashLocator locator;
  TrashManager trash;

  List<String> get trashRoots => [systemTrash, dataTrash];

  ScanRequest get request => ScanRequest(
        roots: [profile, dataDrive],
        exclusions: db.exclusions(),
        trashRoots: trashRoots,
        protectedRoots: guard.config.protectedRoots,
      );

  Scanner get scanner =>
      Scanner(fs: fs, db: db, categorizer: categorizer, clock: clock);

  ScanSummary scan({CancelToken? cancel}) =>
      scanner.run(request, cancel: cancel);

  Reconciler get reconciler => Reconciler(
        fs: fs,
        db: db,
        trash: trash,
        categorizer: categorizer,
        clock: clock,
      );

  PurgeChecker get purge => PurgeChecker(db: db, fs: fs, clock: clock);

  /// Simulates losing the index (app data cleared, or uninstall and
  /// reinstall): a fresh database and fresh manifest cache.
  void loseIndex() {
    db.close();
    db = IndexDb.inMemory();
    trash = TrashManager(
      fs: fs,
      db: db,
      mutator: mutator,
      locator: locator,
      clock: clock,
    );
  }

  /// An old file: modified two years before "now".
  void addOldFile(String path, {int size = 1000}) => fs.addFile(
        path,
        size: size,
        modified: clock.now().subtract(const Duration(days: 730)),
      );

  int idOf(String path) => db.byPath(path)!.id;
}
