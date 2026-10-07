import 'dart:ffi';
import 'dart:io';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

const _driveRemovable = 2;
const _driveFixed = 3;

enum DriveKind { fixed, removable, other }

final class DriveInfo {
  const DriveInfo({
    required this.root,
    required this.kind,
    required this.totalBytes,
    required this.freeBytes,
  });

  final String root;
  final DriveKind kind;
  final int totalBytes;
  final int freeBytes;

  int get usedBytes => totalBytes - freeBytes;
}

/// Resolves a known folder (handles redirection and OneDrive Known Folder
/// Move); null if it can't be resolved.
String? _knownFolder(String folderId) {
  final guid = GUIDFromString(folderId);
  final out = calloc<Pointer<Utf16>>();
  try {
    final hr = SHGetKnownFolderPath(guid, 0, NULL, out);
    if (FAILED(hr)) return null;
    final path = out.value.toDartString();
    CoTaskMemFree(out.value.cast());
    return path;
  } finally {
    free(guid);
    free(out);
  }
}

String _env(String name, String fallback) =>
    Platform.environment[name] ?? fallback;

/// The current user's folders, including OneDrive roots from the
/// environment variables OneDrive sets.
KnownFolders resolveKnownFolders() {
  final profile = _env('USERPROFILE', r'C:\Users\Default');
  String folder(String id, String name) =>
      _knownFolder(id) ?? winPath.join(profile, name);
  final oneDrive = <String>{
    for (final v in ['OneDrive', 'OneDriveCommercial', 'OneDriveConsumer'])
      if (Platform.environment[v] case final p? when p.isNotEmpty)
        normalizePath(p),
  };
  return KnownFolders(
    userProfile: profile,
    downloads: folder(FOLDERID_Downloads, 'Downloads'),
    documents: folder(FOLDERID_Documents, 'Documents'),
    desktop: folder(FOLDERID_Desktop, 'Desktop'),
    pictures: folder(FOLDERID_Pictures, 'Pictures'),
    videos: folder(FOLDERID_Videos, 'Videos'),
    music: folder(FOLDERID_Music, 'Music'),
    oneDriveRoots: oneDrive.toList(),
  );
}

String windowsDirectory() => _env('SystemRoot', r'C:\Windows');

/// Mounted drives with their capacity. Network drives are excluded.
List<DriveInfo> listDrives() {
  final mask = GetLogicalDrives();
  final drives = <DriveInfo>[];
  for (var i = 0; i < 26; i++) {
    if (mask & (1 << i) == 0) continue;
    final root = '${String.fromCharCode(65 + i)}:\\';
    final rootPtr = root.toNativeUtf16();
    final freeToCaller = calloc<Uint64>();
    final total = calloc<Uint64>();
    final totalFree = calloc<Uint64>();
    try {
      final type = GetDriveType(rootPtr);
      final kind = switch (type) {
        _driveFixed => DriveKind.fixed,
        _driveRemovable => DriveKind.removable,
        _ => DriveKind.other,
      };
      if (kind == DriveKind.other) continue;
      if (GetDiskFreeSpaceEx(rootPtr, freeToCaller, total, totalFree) == 0) {
        continue;
      }
      drives.add(DriveInfo(
        root: root,
        kind: kind,
        totalBytes: total.value,
        freeBytes: freeToCaller.value,
      ));
    } finally {
      free(rootPtr);
      free(freeToCaller);
      free(total);
      free(totalFree);
    }
  }
  return drives;
}

/// Opens File Explorer at [path].
Future<void> openInExplorer(String path) =>
    Process.run('explorer.exe', [path]);
