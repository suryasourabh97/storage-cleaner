import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

// File attribute bits (winnt.h). Defined here so we don't depend on which
// of these a given win32 package version exports.
const _attrHidden = 0x00000002;
const _attrSystem = 0x00000004;
const _attrDirectory = 0x00000010;
const _attrReparsePoint = 0x00000400;
const _attrOffline = 0x00001000;
const _attrRecallOnOpen = 0x00040000;
const _attrPinned = 0x00080000;
const _attrRecallOnDataAccess = 0x00400000;

/// IsReparseTagNameSurrogate: junctions, symlinks, mount points. Cloud-file
/// (OneDrive) tags are not name surrogates.
const _nameSurrogateBit = 0x20000000;

// Win32 error codes.
const _errFileNotFound = 2;
const _errPathNotFound = 3;
const _errAccessDenied = 5;
const _errNotSameDevice = 17;
const _errSharingViolation = 32;
const _errLockViolation = 33;
const _errFileExists = 80;
const _errAlreadyExists = 183;

const _moveReplaceExisting = 0x1;
const _moveWriteThrough = 0x8;

/// Converts a FILETIME (100 ns ticks since 1601-01-01 UTC) to UTC DateTime.
DateTime fileTimeToDateTime(int high, int low) {
  final ticks = (high << 32) | low;
  const epochDiffMicros = 11644473600000000;
  return DateTime.fromMicrosecondsSinceEpoch(
    ticks ~/ 10 - epochDiffMicros,
    isUtc: true,
  );
}

/// Classifies raw attributes and reparse tag into [FileAttrs].
FileAttrs attrsFrom(int attributes, int reparseTag) {
  final isReparse = attributes & _attrReparsePoint != 0;
  return FileAttrs(
    hidden: attributes & _attrHidden != 0,
    system: attributes & _attrSystem != 0,
    isLink: isReparse && (reparseTag & _nameSurrogateBit) != 0,
    onlineOnly: attributes &
            (_attrRecallOnDataAccess | _attrRecallOnOpen | _attrOffline) !=
        0,
    pinned: attributes & _attrPinned != 0,
  );
}

/// [PlatformFs] backed by Win32 (ADR-001). Never opens file contents while
/// listing; never copies on move.
final class WindowsPlatformFs implements PlatformFs {
  final Map<String, (int?, DateTime)> _serialCache = {};

  /// `\\?\` prefix lifts the 260-character path limit.
  static String _long(String path) {
    final p = normalizePath(path);
    if (p.startsWith(r'\\?\')) return p;
    if (p.startsWith(r'\\')) return '\\\\?\\UNC\\${p.substring(2)}';
    return '\\\\?\\$p';
  }

  static bool _isDriveRoot(String path) =>
      samePath(driveRoot(path), path);

  static FsErrorCode _code(int err) => switch (err) {
        _errFileNotFound || _errPathNotFound => FsErrorCode.notFound,
        _errAccessDenied => FsErrorCode.accessDenied,
        _errNotSameDevice => FsErrorCode.crossVolume,
        _errSharingViolation || _errLockViolation => FsErrorCode.inUse,
        _errFileExists || _errAlreadyExists => FsErrorCode.alreadyExists,
        _ => FsErrorCode.io,
      };

  static FsException _error(String path, [int? err]) {
    final e = err ?? GetLastError();
    return FsException(_code(e), path, 'Win32 error $e');
  }

  FsEntry _entry(String path, WIN32_FIND_DATA d, int serial) {
    final attributes = d.dwFileAttributes;
    return FsEntry(
      path: path,
      isDirectory: attributes & _attrDirectory != 0,
      size: (d.nFileSizeHigh << 32) | d.nFileSizeLow,
      modified: fileTimeToDateTime(
        d.ftLastWriteTime.dwHighDateTime,
        d.ftLastWriteTime.dwLowDateTime,
      ),
      volumeSerial: serial,
      attrs: attrsFrom(attributes, d.dwReserved0),
    );
  }

  @override
  int? volumeSerialOf(String path) {
    final root = driveRoot(path);
    final key = pathKey(root);
    final cached = _serialCache[key];
    final now = DateTime.now();
    if (cached != null && now.difference(cached.$2).inSeconds < 2) {
      return cached.$1;
    }
    final rootPtr = root.toNativeUtf16();
    final serialPtr = calloc<Uint32>();
    try {
      final ok = GetVolumeInformation(
        rootPtr,
        nullptr,
        0,
        serialPtr,
        nullptr,
        nullptr,
        nullptr,
        0,
      );
      final serial = ok == 0 ? null : serialPtr.value;
      _serialCache[key] = (serial, now);
      return serial;
    } finally {
      free(rootPtr);
      free(serialPtr);
    }
  }

  @override
  FsEntry? stat(String path) {
    final serial = volumeSerialOf(path);
    if (serial == null) return null;
    if (_isDriveRoot(path)) {
      return FsEntry(
        path: driveRoot(path),
        isDirectory: true,
        size: 0,
        modified: DateTime.utc(1970),
        volumeSerial: serial,
      );
    }
    final data = calloc<WIN32_FIND_DATA>();
    final p = _long(path).toNativeUtf16();
    try {
      final h = FindFirstFile(p, data);
      if (h == INVALID_HANDLE_VALUE) {
        final err = GetLastError();
        if (err == _errFileNotFound || err == _errPathNotFound) return null;
        throw _error(path, err);
      }
      FindClose(h);
      return _entry(normalizePath(path), data.ref, serial);
    } finally {
      free(p);
      free(data);
    }
  }

  @override
  List<FsEntry> list(String dirPath) {
    final serial = volumeSerialOf(dirPath);
    if (serial == null) throw FsException(FsErrorCode.notFound, dirPath);
    final dir = normalizePath(dirPath);
    final pattern = dir.endsWith(r'\') ? '$dir*' : '$dir\\*';
    final data = calloc<WIN32_FIND_DATA>();
    final p = _long(pattern).toNativeUtf16();
    final out = <FsEntry>[];
    try {
      final h = FindFirstFile(p, data);
      if (h == INVALID_HANDLE_VALUE) {
        final err = GetLastError();
        if (err == _errFileNotFound) return out; // empty
        throw _error(dirPath, err);
      }
      try {
        do {
          final name = data.ref.cFileName;
          if (name == '.' || name == '..') continue;
          out.add(_entry(winPath.join(dir, name), data.ref, serial));
        } while (FindNextFile(h, data) != 0);
      } finally {
        FindClose(h);
      }
      return out;
    } finally {
      free(p);
      free(data);
    }
  }

  void _moveEx(String from, String to, int flags) {
    final a = _long(from).toNativeUtf16();
    final b = _long(to).toNativeUtf16();
    try {
      if (MoveFileEx(a, b, flags) == 0) throw _error(from);
    } finally {
      free(a);
      free(b);
    }
  }

  /// Same-volume rename only: no MOVEFILE_COPY_ALLOWED, no replace.
  @override
  void move(String from, String to) => _moveEx(from, to, 0);

  @override
  void delete(String path) {
    final p = _long(path).toNativeUtf16();
    try {
      if (DeleteFile(p) == 0) throw _error(path);
    } finally {
      free(p);
    }
  }

  @override
  void dehydrate(String path) => throw FsException(
        FsErrorCode.io,
        path,
        'Free up space is not available yet',
      );

  @override
  void createDirectories(String path) {
    try {
      Directory(path).createSync(recursive: true);
    } on FileSystemException catch (e) {
      throw FsException(_code(e.osError?.errorCode ?? 0), path, e.message);
    }
  }

  @override
  Uint8List readBytes(String path) {
    try {
      return File(path).readAsBytesSync();
    } on FileSystemException catch (e) {
      throw FsException(_code(e.osError?.errorCode ?? 0), path, e.message);
    }
  }

  @override
  void writeBytes(String path, List<int> bytes) {
    try {
      File(path).writeAsBytesSync(bytes, flush: true);
    } on FileSystemException catch (e) {
      throw FsException(_code(e.osError?.errorCode ?? 0), path, e.message);
    }
  }

  @override
  void replaceFile(String source, String target) =>
      _moveEx(source, target, _moveReplaceExisting | _moveWriteThrough);
}
