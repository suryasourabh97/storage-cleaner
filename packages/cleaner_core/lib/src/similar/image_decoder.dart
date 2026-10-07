import 'dart:typed_data';

/// Side of the square grayscale rendition decoders produce.
const fingerprintSide = 64;

/// A photo reduced to what similarity needs.
final class DecodedImage {
  const DecodedImage({
    required this.width,
    required this.height,
    required this.gray,
    required this.colorSig,
  });

  /// Full dimensions after EXIF orientation is applied.
  final int width;
  final int height;

  /// [fingerprintSide]² luminance values, row-major, image squashed to a
  /// square (aspect is ignored for hashing, as in standard pHash).
  final Uint8List gray;

  /// Mean R, G, B of each cell in a 4×4 grid (48 bytes).
  final Uint8List colorSig;
}

enum DecodeFailure {
  /// HEIC/HEIF and other formats without a decoder.
  unsupportedFormat,
  corrupt,
  unreadable,
}

sealed class DecodeResult {
  const DecodeResult();
}

final class DecodeOk extends DecodeResult {
  const DecodeOk(this.image);
  final DecodedImage image;
}

final class DecodeFailed extends DecodeResult {
  const DecodeFailed(this.reason);
  final DecodeFailure reason;
}

/// Turns a photo file into a [DecodedImage]. Implemented with Flutter's
/// engine codecs in the app (ADR-007) and by fakes in tests.
abstract interface class ImageDecoder {
  Future<DecodeResult> decode(String path);
}

/// EXIF orientation (1–8) from the start of a JPEG file; 1 if absent.
/// Values 5–8 mean the stored image is rotated by 90° (width/height swap).
int exifOrientation(Uint8List bytes) {
  int u16(int o, bool le) =>
      le ? bytes[o] | (bytes[o + 1] << 8) : (bytes[o] << 8) | bytes[o + 1];
  int u32(int o, bool le) => le
      ? bytes[o] | (bytes[o + 1] << 8) | (bytes[o + 2] << 16) | (bytes[o + 3] << 24)
      : (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];

  if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return 1;
  var i = 2;
  while (i + 4 <= bytes.length) {
    if (bytes[i] != 0xFF) return 1;
    final marker = bytes[i + 1];
    if (marker == 0xDA || marker == 0xD9) return 1; // image data starts
    final len = u16(i + 2, false);
    final seg = i + 4;
    if (marker == 0xE1 &&
        seg + 14 <= bytes.length &&
        bytes[seg] == 0x45 && // 'E'
        bytes[seg + 1] == 0x78 && // 'x'
        bytes[seg + 2] == 0x69 && // 'i'
        bytes[seg + 3] == 0x66) {
      // 'f'
      final tiff = seg + 6;
      final le = bytes[tiff] == 0x49; // 'II'
      final ifd = tiff + u32(tiff + 4, le);
      if (ifd + 2 > bytes.length) return 1;
      final count = u16(ifd, le);
      for (var e = 0; e < count; e++) {
        final entry = ifd + 2 + e * 12;
        if (entry + 12 > bytes.length) return 1;
        if (u16(entry, le) == 0x0112) {
          final v = u16(entry + 8, le);
          return v >= 1 && v <= 8 ? v : 1;
        }
      }
      return 1;
    }
    i = seg + len - 2;
  }
  return 1;
}
