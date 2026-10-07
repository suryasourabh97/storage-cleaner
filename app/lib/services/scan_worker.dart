import 'dart:ffi';
import 'dart:isolate';

import 'package:cleaner_core/cleaner_core.dart';

import '../platform/windows/windows_fs.dart';

/// Message sent when the worker fails.
final class ScanFailed {
  const ScanFailed(this.error, this.stack);
  final String error;
  final String stack;
}

/// Everything the background scan needs; all fields are plain data so they
/// can cross the isolate boundary.
typedef ScanJob = ({
  String dbPath,
  ScanRequest request,
  KnownFolders folders,
  int cancelFlagAddress,
  SendPort port,
});

/// Isolate entry point. Opens its own database connection (WAL mode lets
/// the UI keep reading), scans, and reports progress and the summary.
void scanWorker(ScanJob job) {
  IndexDb? db;
  try {
    db = IndexDb.open(job.dbPath);
    final flag = Pointer<Int32>.fromAddress(job.cancelFlagAddress);
    final summary = Scanner(
      fs: WindowsPlatformFs(),
      db: db,
      categorizer: Categorizer(job.folders),
      clock: const SystemClock(),
    ).run(
      job.request,
      cancel: CancelToken(() => flag.value != 0),
      onProgress: job.port.send,
    );
    job.port.send(summary);
  } catch (e, st) {
    job.port.send(ScanFailed('$e', '$st'));
  } finally {
    db?.close();
  }
}
