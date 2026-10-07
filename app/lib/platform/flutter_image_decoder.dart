import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cleaner_core/cleaner_core.dart';

/// Decodes photos with Flutter's engine codecs (ADR-007): dimensions from
/// the encoded header, a 64×64 rendition decoded at reduced size, EXIF
/// orientation applied to the dimensions.
final class FlutterImageDecoder implements ImageDecoder {
  const FlutterImageDecoder();

  /// No engine codec for these yet (counted as "could not be checked").
  static const unsupported = {
    '.heic', '.heif', '.avif', '.tif', '.tiff', '.svg',
    '.raw', '.cr2', '.cr3', '.nef', '.arw', '.dng',
  };

  @override
  Future<DecodeResult> decode(String path) async {
    final ext = winPath.extension(path).toLowerCase();
    if (unsupported.contains(ext)) {
      return const DecodeFailed(DecodeFailure.unsupportedFormat);
    }
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException {
      return const DecodeFailed(DecodeFailure.unreadable);
    }
    return decodeBytes(bytes);
  }

  /// Exposed for tests that build images in memory.
  static Future<DecodeResult> decodeBytes(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    ui.Image? image;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      var width = descriptor.width;
      var height = descriptor.height;
      if (exifOrientation(bytes) >= 5) {
        final t = width;
        width = height;
        height = t;
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: fingerprintSide,
        targetHeight: fingerprintSide,
      );
      image = (await codec.getNextFrame()).image;
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return const DecodeFailed(DecodeFailure.corrupt);
      return DecodeOk(fromRgba(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        image.width,
        image.height,
        width: width,
        height: height,
      ));
    } catch (_) {
      return const DecodeFailed(DecodeFailure.corrupt);
    } finally {
      image?.dispose();
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// Builds the fingerprint inputs from RGBA pixels of size [w]×[h]
  /// (normally [fingerprintSide]²).
  static DecodedImage fromRgba(
    Uint8List rgba,
    int w,
    int h, {
    required int width,
    required int height,
  }) {
    const s = fingerprintSide;
    final gray = Uint8List(s * s);
    final sum = Float64List(48);
    final count = Int32List(16);
    for (var y = 0; y < s; y++) {
      final sy = y * h ~/ s;
      for (var x = 0; x < s; x++) {
        final sx = x * w ~/ s;
        final o = (sy * w + sx) * 4;
        final r = rgba[o], g = rgba[o + 1], b = rgba[o + 2];
        gray[y * s + x] = (0.299 * r + 0.587 * g + 0.114 * b).round();
        final cell = (y * 4 ~/ s) * 4 + (x * 4 ~/ s);
        sum[cell * 3] += r;
        sum[cell * 3 + 1] += g;
        sum[cell * 3 + 2] += b;
        count[cell]++;
      }
    }
    final sig = Uint8List(48);
    for (var c = 0; c < 16; c++) {
      for (var k = 0; k < 3; k++) {
        sig[c * 3 + k] = (sum[c * 3 + k] / count[c]).round();
      }
    }
    return DecodedImage(width: width, height: height, gray: gray, colorSig: sig);
  }
}
