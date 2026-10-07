import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../model/models.dart';
import '../platform/platform_fs.dart';

/// Thrown inside hashing when the operation is cancelled.
final class HashCancelled implements Exception {
  const HashCancelled();
}

final class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}

/// Content hashing for the duplicate pipeline (ADR-004). Reads through
/// [PlatformFs.readRange] so tests can count every byte read.
final class ContentHasher {
  ContentHasher(this._fs, {this.chunkSize = 1 << 20, this.sampleSize = 64 * 1024});

  final PlatformFs _fs;
  final int chunkSize;
  final int sampleSize;

  /// Hash of the first, middle and last [sampleSize] bytes (or the whole
  /// file if it is small). Cheap way to rule out most same-size files.
  String sample(String path, int size) {
    final out = _DigestSink();
    final sink = sha256.startChunkedConversion(out);
    sink.add(_le64(size));
    if (size <= sampleSize * 3) {
      sink.add(_fs.readRange(path, 0, size));
    } else {
      sink.add(_fs.readRange(path, 0, sampleSize));
      sink.add(_fs.readRange(path, size ~/ 2 - sampleSize ~/ 2, sampleSize));
      sink.add(_fs.readRange(path, size - sampleSize, sampleSize));
    }
    sink.close();
    return 's:${out.value}';
  }

  /// SHA-256 of the whole file. Calls [onBytes] after each chunk and checks
  /// [cancel] between chunks.
  String full(
    String path,
    int size, {
    CancelToken? cancel,
    void Function(int bytes)? onBytes,
  }) {
    final out = _DigestSink();
    final sink = sha256.startChunkedConversion(out);
    var offset = 0;
    while (offset < size) {
      if (cancel?.isCancelled ?? false) throw const HashCancelled();
      final chunk = _fs.readRange(path, offset, chunkSize);
      if (chunk.isEmpty) break; // file shrank; caller re-checks stat
      sink.add(chunk);
      offset += chunk.length;
      onBytes?.call(chunk.length);
    }
    sink.close();
    return 'f:${out.value}';
  }

  static Uint8List _le64(int v) =>
      Uint8List(8)..buffer.asByteData().setUint64(0, v, Endian.little);
}
