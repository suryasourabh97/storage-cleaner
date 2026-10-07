import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../platform/flutter_image_decoder.dart';
import '../platform/windows/system_info.dart';
import '../platform/windows/windows_fs.dart';
import 'scan_worker.dart';
import 'settings.dart';

/// Totals shown on the Home screen.
final class Overview {
  const Overview({
    required this.oldCount,
    required this.oldBytes,
    required this.largeCount,
    required this.largeBytes,
    required this.duplicateGroups,
    required this.duplicateBytes,
    required this.similarGroups,
    required this.similarBytes,
    required this.trashCount,
    required this.trashBytes,
    required this.purgeReady,
    required this.reclaimableByDrive,
  });

  final int oldCount;
  final int oldBytes;
  final int largeCount;
  final int largeBytes;
  final int duplicateGroups;
  final int duplicateBytes;
  final int similarGroups;

  /// Copies preselected by default (edited groups excluded).
  final int similarBytes;
  final int trashCount;
  final int trashBytes;
  final PurgeSummary purgeReady;

  /// Space the user could get back per drive root (old, large and extra
  /// duplicate copies, each file counted once; OneDrive files excluded
  /// until "Free up space" exists).
  final Map<String, int> reclaimableByDrive;

  int get reclaimableTotal =>
      reclaimableByDrive.values.fold(0, (s, v) => s + v);
}

/// Wires the engine to Windows and holds UI state.
final class AppController extends ChangeNotifier {
  AppController._({
    required this.fs,
    required this.db,
    required this.dbPath,
    required this.settingsPath,
    required this.settings,
    required this.folders,
    this.includeOtherDrives = true,
  }) {
    _rebuildEngine();
  }

  /// Opens (or creates) the app's data and reconciles the trash.
  ///
  /// The optional arguments exist for tests and screenshots: a separate data
  /// folder, a stand-in user profile, and no scanning of other drives.
  static AppController open({
    String? dataDirOverride,
    KnownFolders? foldersOverride,
    bool includeOtherDrives = true,
  }) {
    final local = Platform.environment['LOCALAPPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Local';
    final roaming = Platform.environment['APPDATA'] ??
        '${Platform.environment['USERPROFILE']}\\AppData\\Roaming';
    final dataDir = Directory(dataDirOverride ?? '$local\\StorageCleaner')
      ..createSync(recursive: true);
    final dbPath = '${dataDir.path}\\index.db';
    final settingsPath = dataDirOverride == null
        ? '$roaming\\StorageCleaner\\settings.json'
        : '$dataDirOverride\\settings.json';

    final c = AppController._(
      fs: WindowsPlatformFs(),
      db: IndexDb.open(dbPath),
      dbPath: dbPath,
      settingsPath: settingsPath,
      settings: AppSettings.load(settingsPath),
      folders: foldersOverride ?? resolveKnownFolders(),
      includeOtherDrives: includeOtherDrives,
    );
    c.lastReconcile = c.reconciler.run(trashRoots: c.trashRoots);
    return c;
  }

  final WindowsPlatformFs fs;
  final IndexDb db;
  final String dbPath;
  final String settingsPath;
  final AppSettings settings;
  final KnownFolders folders;
  final bool includeOtherDrives;
  static const clock = SystemClock();

  late List<DriveInfo> drives;
  late List<String> scanRoots;
  late List<String> trashRoots;
  late List<String> protectedRoots;
  late PathGuard guard;
  late FileMutator mutator;
  late TrashLocator locator;
  late TrashManager trash;
  late Reconciler reconciler;
  late PurgeChecker purge;
  late Categorizer categorizer;
  ReconcileReport? lastReconcile;

  /// Recomputes drives, roots and the engine (drives can be plugged in or
  /// out; the removable-drive setting can change).
  void _rebuildEngine() {
    drives = listDrives();
    final profile = folders.userProfile;
    final systemDrive = driveRoot(profile);
    final allRoots = [for (final d in drives) d.root];
    scanRoots = [
      profile,
      for (final d in drives)
        if (includeOtherDrives &&
            !samePath(d.root, systemDrive) &&
            (d.kind == DriveKind.fixed ||
                (d.kind == DriveKind.removable &&
                    settings.scanRemovableDrives)))
          d.root,
    ];
    locator = TrashLocator(userProfile: profile);
    trashRoots = locator.trashRootsFor(allRoots);
    protectedRoots = defaultProtectedRoots(
      windowsDir: windowsDirectory(),
      userProfile: profile,
      driveRoots: allRoots,
    );
    guard = PathGuard(
      fs,
      GuardConfig(
        allowedRoots: [...scanRoots, ...trashRoots],
        protectedRoots: protectedRoots,
      ),
    );
    mutator = FileMutator(fs, guard);
    categorizer = Categorizer(folders);
    trash = TrashManager(
      fs: fs,
      db: db,
      mutator: mutator,
      locator: locator,
      clock: clock,
    );
    reconciler = Reconciler(
      fs: fs,
      db: db,
      trash: trash,
      categorizer: categorizer,
      clock: clock,
    );
    purge = PurgeChecker(db: db, fs: fs, clock: clock);
  }

  void refreshDrives() {
    _rebuildEngine();
    notifyListeners();
  }

  // ---------------------------------------------------------------- scan

  bool scanning = false;
  ScanProgress? progress;
  ScanSummary? lastScan;
  String? scanError;
  Pointer<Int32>? _cancelFlag;

  ScanRun? get latestRun => db.latestScanRun();

  Future<void> scan() async {
    if (scanning || analyzing) return;
    _rebuildEngine();
    scanning = true;
    progress = null;
    scanError = null;
    notifyListeners();

    final flag = calloc<Int32>()..value = 0;
    _cancelFlag = flag;
    final port = ReceivePort();
    final request = ScanRequest(
      roots: scanRoots,
      exclusions: db.exclusions(),
      trashRoots: trashRoots,
      protectedRoots: protectedRoots,
    );
    try {
      await Isolate.spawn<ScanJob>(
        scanWorker,
        (
          dbPath: dbPath,
          request: request,
          folders: folders,
          cancelFlagAddress: flag.address,
          port: port.sendPort,
        ),
        onExit: port.sendPort,
        onError: port.sendPort,
      );
      await for (final msg in port) {
        if (msg is ScanProgress) {
          progress = msg;
          notifyListeners();
        } else if (msg is ScanSummary) {
          lastScan = msg;
        } else if (msg is ScanFailed) {
          scanError = msg.error;
        } else if (msg is List) {
          scanError = '${msg.first}';
        } else if (msg == null) {
          break; // isolate exited
        }
      }
    } catch (e) {
      scanError = '$e';
    } finally {
      port.close();
      _cancelFlag = null;
      calloc.free(flag);
      scanning = false;
      notifyListeners();
    }
  }

  void cancelScan() {
    _cancelFlag?.value = 1;
  }

  /// Set by Home's purge banner; consumed by the Trash screen.
  bool purgeReviewRequested = false;

  // ------------------------------------------------------------- queries

  List<Candidate> oldFilesList() =>
      oldFiles(db, threshold: settings.age, now: clock.now());

  List<Candidate> largeFilesList() =>
      largeFiles(db, threshold: settings.size, now: clock.now());

  List<TrashItem> trashList() => purge.trashItems();

  Overview overview() {
    int sum(Iterable<Candidate> c) => c.fold(0, (s, x) => s + x.record.size);
    final old = oldFilesList();
    final large = largeFilesList();
    final dups = duplicateGroupsList();
    final similar = similarGroupsList();
    final t = trashList();

    final byId = <int, FileRecord>{};
    for (final c in [...old, ...large]) {
      if (c.action == CandidateAction.trash) byId[c.record.id] = c.record;
    }
    for (final g in dups) {
      for (final m in g.members.skip(1)) {
        byId[m.id] = m;
      }
    }
    var similarBytes = 0;
    for (final g in similar) {
      for (final m in g.members.where((m) => g.defaultRemovals.contains(m.id))) {
        byId[m.id] = m;
        similarBytes += m.size;
      }
    }
    final byDrive = <String, int>{};
    for (final r in byId.values) {
      final d = driveRoot(r.path).toUpperCase();
      byDrive[d] = (byDrive[d] ?? 0) + r.size;
    }

    return Overview(
      oldCount: old.length,
      oldBytes: sum(old),
      largeCount: large.length,
      largeBytes: sum(large),
      duplicateGroups: dups.length,
      duplicateBytes: dups.fold(0, (s, g) => s + g.reclaimable),
      similarGroups: similar.length,
      similarBytes: similarBytes,
      trashCount: t.length,
      trashBytes: t.fold(0, (s, x) => s + x.record.size),
      purgeReady: purge.check(),
      reclaimableByDrive: byDrive,
    );
  }

  // ---------------------------------------------------------- duplicates

  bool analyzing = false;
  AnalysisProgress? analysisProgress;
  AnalysisSummary? lastAnalysis;
  SimilarSummary? lastSimilar;
  String? analysisError;

  (DateTime, RunStatus)? get latestAnalysis =>
      db.latestAnalysis('duplicates');

  List<DuplicateGroup> duplicateGroupsList() => duplicateGroups(
        db,
        minSize: settings.duplicateMin.bytes,
        exclusions: db.exclusions(),
        rules: KeepRules(folders),
      );

  Future<void> findDuplicates() async {
    if (analyzing || scanning) return;
    analyzing = true;
    analysisProgress = null;
    analysisError = null;
    notifyListeners();

    final flag = calloc<Int32>()..value = 0;
    _cancelFlag = flag;
    final port = ReceivePort();
    try {
      await Isolate.spawn<AnalysisJob>(
        analysisWorker,
        (
          dbPath: dbPath,
          minSize: settings.duplicateMin.bytes,
          exclusions: db.exclusions(),
          cancelFlagAddress: flag.address,
          port: port.sendPort,
        ),
        onExit: port.sendPort,
        onError: port.sendPort,
      );
      await for (final msg in port) {
        if (msg is AnalysisProgress) {
          analysisProgress = msg;
          notifyListeners();
        } else if (msg is AnalysisSummary) {
          lastAnalysis = msg;
        } else if (msg is ScanFailed) {
          analysisError = msg.error;
        } else if (msg is List) {
          analysisError = '${msg.first}';
        } else if (msg == null) {
          break;
        }
      }
      final cancelled = flag.value != 0;
      if (settings.similarPhotos && !cancelled && analysisError == null) {
        lastSimilar = await SimilarPhotoFinder(
          fs: fs,
          db: db,
          decoder: const FlutterImageDecoder(),
          clock: clock,
        ).run(
          exclusions: db.exclusions(),
          cancel: CancelToken(() => flag.value != 0),
          rules: KeepRules(folders),
          onProgress: (p) {
            analysisProgress = p;
            notifyListeners();
          },
        );
      }
    } catch (e) {
      analysisError = '$e';
    } finally {
      port.close();
      _cancelFlag = null;
      calloc.free(flag);
      analyzing = false;
      notifyListeners();
    }
  }

  (DateTime, RunStatus)? get latestSimilar => db.latestAnalysis('similar');

  List<SimilarGroup> similarGroupsList() => settings.similarPhotos
      ? similarPhotoGroups(
          db,
          exclusions: db.exclusions(),
          rules: KeepRules(folders),
        )
      : const [];

  BatchResult removeSimilarCopies(List<SimilarRemoval> removals) {
    final r = removeSimilar(removals, db: db, fs: fs, trash: trash);
    notifyListeners();
    return r;
  }

  void setSimilarPhotos(bool v) {
    settings.similarPhotos = v;
    settings.save(settingsPath);
    notifyListeners();
  }

  BatchResult removeDuplicateCopies(List<DuplicateRemoval> removals) {
    final r = removeDuplicates(removals, db: db, fs: fs, trash: trash);
    notifyListeners();
    return r;
  }

  void setDuplicateMin(DuplicateMinSize v) {
    settings.duplicateMin = v;
    settings.save(settingsPath);
    notifyListeners();
  }

  // ------------------------------------------------------------- actions

  BatchResult moveToTrash(Iterable<int> ids) {
    final r = trash.moveToTrash(ids);
    notifyListeners();
    return r;
  }

  RestoreResult restore(int id, {RestoreChoice? choice}) {
    final r = trash.restore(id, choice: choice);
    notifyListeners();
    return r;
  }

  BatchResult deletePermanently(
    Iterable<int> ids,
    DeletionConfirmation confirmation,
  ) {
    final r = trash.deletePermanently(ids, confirmation);
    notifyListeners();
    return r;
  }

  // ------------------------------------------------------------ settings

  void setAge(AgeThreshold a) {
    settings.age = a;
    settings.save(settingsPath);
    notifyListeners();
  }

  void setSize(SizeThreshold s) {
    settings.size = s;
    settings.save(settingsPath);
    notifyListeners();
  }

  void setScanRemovable(bool v) {
    settings.scanRemovableDrives = v;
    settings.save(settingsPath);
    refreshDrives();
  }

  List<String> get exclusions => db.exclusions();

  void addExclusion(String path) {
    db.addExclusion(path);
    notifyListeners();
  }

  void removeExclusion(String path) {
    db.removeExclusion(path);
    notifyListeners();
  }

  @override
  void dispose() {
    cancelScan();
    db.close();
    super.dispose();
  }
}
