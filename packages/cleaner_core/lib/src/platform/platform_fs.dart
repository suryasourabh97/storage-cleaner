import 'dart:typed_data';

import '../model/models.dart';

/// Error categories a platform file-system call can fail with.
enum FsErrorCode {
  notFound,
  alreadyExists,
  inUse,
  accessDenied,
  crossVolume,
  notEmpty,
  io,
}

final class FsException implements Exception {
  const FsException(this.code, this.path, [this.message]);
  final FsErrorCode code;
  final String path;
  final String? message;

  @override
  String toString() =>
      'FsException($code, $path${message == null ? '' : ': $message'})';
}

/// Synchronous file-system access. Implemented with Win32 via FFI in the app
/// and by `MemoryPlatformFs` in tests.
///
/// Only `FileMutator` may call [move], [delete] and [dehydrate] on user files
/// (ADR-006, enforced by a source-scan test).
abstract interface class PlatformFs {
  /// Metadata for [path], or null if it does not exist. Never follows links
  /// and never reads file contents.
  FsEntry? stat(String path);

  /// Entries directly inside [dirPath]. Throws [FsException] if the directory
  /// can't be read. Never reads file contents.
  List<FsEntry> list(String dirPath);

  /// Volume serial number of the drive containing [path], or null if the
  /// drive is not mounted.
  int? volumeSerialOf(String path);

  /// Same-volume rename. Never copies. Fails if [to] exists.
  void move(String from, String to);

  /// Permanently deletes a file (not a directory).
  void delete(String path);

  /// Asks the cloud provider to keep the file online-only (OneDrive
  /// "Free up space").
  void dehydrate(String path);

  void createDirectories(String path);

  Uint8List readBytes(String path);

  /// Writes app-owned metadata files (manifests, README). Not for user files.
  void writeBytes(String path, List<int> bytes);

  /// Atomically replaces [target] with [source] (used for manifest writes).
  void replaceFile(String source, String target);
}
