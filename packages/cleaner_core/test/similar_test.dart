@Tags(['safety'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:test/test.dart';

import 'support.dart';

/// A synthetic "photo": a few soft-edged coloured shapes on a gradient.
/// Rendered at [fingerprintSide]² the way a decoder would hand it over.
final class Scene {
  const Scene(this.seed, {this.shiftX = 0});
  final int seed;

  /// Moves every shape right by this fraction of the width (burst shots).
  final double shiftX;

  (double, double, double) colorAt(double x, double y) {
    final rnd = math.Random(seed);
    var r = 40 + 120 * x, g = 60 + 100 * y, b = 90 + 60 * (1 - x);
    for (var k = 0; k < 6; k++) {
      final cx = rnd.nextDouble() + shiftX, cy = rnd.nextDouble();
      final rad = 0.08 + rnd.nextDouble() * 0.15;
      final cr = rnd.nextDouble() * 255,
          cg = rnd.nextDouble() * 255,
          cb = rnd.nextDouble() * 255;
      final d = math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
      final w = (1 - ((d - rad) / 0.03)).clamp(0.0, 1.0);
      r = r * (1 - w) + cr * w;
      g = g * (1 - w) + cg * w;
      b = b * (1 - w) + cb * w;
    }
    return (r, g, b);
  }
}

/// Renders [scene] the way a decoder would, with optional resize jitter,
/// noise (re-compression), brightness/tint (filter) and crop.
///
/// Jitter/noise levels mirror the Windows CI calibration on real encoded
/// files, where resized and re-compressed copies differed by 0–1 bits.
DecodedImage render(
  Scene scene, {
  required int width,
  required int height,
  double jitter = 0,
  int noise = 0,
  double brightness = 1,
  double tintR = 0,
  double cropX = 0,
  int noiseSeed = 1,
}) {
  const s = fingerprintSide;
  final gray = Uint8List(s * s);
  final rgbSum = Float64List(48);
  final rgbCount = Int32List(16);
  final rnd = math.Random(noiseSeed);
  for (var py = 0; py < s; py++) {
    for (var px = 0; px < s; px++) {
      final fx = cropX + (px + 0.5 + jitter) / s * (1 - 2 * cropX);
      final fy = (py + 0.5 + jitter) / s;
      var (r, g, b) = scene.colorAt(fx, fy);
      r = (r * brightness + tintR).clamp(0.0, 255.0);
      g = (g * brightness).clamp(0.0, 255.0);
      b = (b * brightness).clamp(0.0, 255.0);
      final n = noise == 0 ? 0 : rnd.nextInt(2 * noise + 1) - noise;
      gray[py * s + px] =
          (0.299 * r + 0.587 * g + 0.114 * b + n).round().clamp(0, 255);
      final cell = (py * 4 ~/ s) * 4 + (px * 4 ~/ s);
      rgbSum[cell * 3] += r;
      rgbSum[cell * 3 + 1] += g;
      rgbSum[cell * 3 + 2] += b;
      rgbCount[cell]++;
    }
  }
  final sig = Uint8List(48);
  for (var c = 0; c < 16; c++) {
    for (var k = 0; k < 3; k++) {
      sig[c * 3 + k] = (rgbSum[c * 3 + k] / rgbCount[c]).round().clamp(0, 255);
    }
  }
  return DecodedImage(width: width, height: height, gray: gray, colorSig: sig);
}

final class FakeDecoder implements ImageDecoder {
  final Map<String, DecodeResult> images = {};
  final List<String> decoded = [];

  void add(String path, DecodedImage img) =>
      images[pathKey(path)] = DecodeOk(img);
  void fail(String path, DecodeFailure why) =>
      images[pathKey(path)] = DecodeFailed(why);

  @override
  Future<DecodeResult> decode(String path) async {
    decoded.add(path);
    return images[pathKey(path)] ?? const DecodeFailed(DecodeFailure.corrupt);
  }
}

void main() {
  late World w;
  late FakeDecoder decoder;
  var sizeSeq = 300000;

  setUp(() {
    w = World();
    decoder = FakeDecoder();
  });

  /// Adds a photo file (unique size so it isn't an exact duplicate) and
  /// what the decoder returns for it.
  void photo(String path, DecodedImage img, {int? size, DateTime? modified}) {
    w.fs.addFile(path, size: size ?? sizeSeq++, modified: modified);
    decoder.add(path, img);
  }

  Future<SimilarSummary> analyze() => SimilarPhotoFinder(
        fs: w.fs,
        db: w.db,
        decoder: decoder,
        clock: w.clock,
      ).run(rules: KeepRules(w.categorizer.folders));

  List<SimilarGroup> groups() =>
      similarPhotoGroups(w.db, rules: KeepRules(w.categorizer.folders));

  const original = r'C:\Users\surya\Pictures\Trip\IMG_1001.jpg';
  const a = Scene(11);

  group('hashing', () {
    test('hamming counts differing bits, including the sign bit', () {
      expect(hamming(0, 0), 0);
      expect(hamming(0, -1), 64);
      expect(hamming(1 << 63, 0), 1);
    });

    test('a resized, re-compressed copy hashes nearly the same', () {
      final x = render(a, width: 4000, height: 3000);
      final y = render(a, width: 1600, height: 1200, jitter: 0.15, noise: 2);
      expect(hamming(perceptualHash(x.gray), perceptualHash(y.gray)),
          lessThanOrEqualTo(4));
      expect(hamming(differenceHash(x.gray), differenceHash(y.gray)),
          lessThanOrEqualTo(4));
    });

    test('different photos hash far apart', () {
      final x = render(a, width: 4000, height: 3000);
      final y = render(const Scene(99), width: 4000, height: 3000);
      expect(hamming(perceptualHash(x.gray), perceptualHash(y.gray)),
          greaterThan(10));
    });
  });

  group('grouping (labelled set)', () {
    test('resized copies are grouped and the largest is kept', () async {
      photo(original, render(a, width: 4000, height: 3000), size: 4200000);
      photo(r'C:\Users\surya\Downloads\IMG_1001 (WhatsApp).jpg',
          render(a, width: 1600, height: 1200, jitter: 0.15, noise: 2),
          size: 350000);
      w.scan();
      final s = await analyze();
      expect(s.fingerprinted, 2);
      final g = groups().single;
      expect(g.best.path, original);
      expect(g.edited, isFalse);
      expect(g.defaultRemovals, {g.members[1].id});
    });

    test('burst shots of the same scene are not grouped', () async {
      photo(original, render(a, width: 4000, height: 3000));
      photo(r'C:\Users\surya\Pictures\Trip\IMG_1002.jpg',
          render(const Scene(11, shiftX: 0.18), width: 4000, height: 3000));
      w.scan();
      await analyze();
      expect(groups(), isEmpty);
    });

    test('unrelated photos are not grouped', () async {
      for (var i = 0; i < 6; i++) {
        photo('C:\\Users\\surya\\Pictures\\p$i.jpg',
            render(Scene(100 + i), width: 3000, height: 2000));
      }
      w.scan();
      await analyze();
      expect(groups(), isEmpty);
    });

    test('a filtered copy is flagged as edited and nothing is preselected',
        () async {
      photo(original, render(a, width: 4000, height: 3000), size: 4200000);
      photo(r'C:\Users\surya\Pictures\Trip\IMG_1001-warm.jpg',
          render(a, width: 4000, height: 3000, brightness: 1.05, tintR: 40),
          size: 4100000);
      w.scan();
      await analyze();
      final gs = groups();
      // Either recognised as an edited copy, or not grouped at all; never
      // auto-selected for removal.
      for (final g in gs) {
        expect(g.edited, isTrue);
        expect(g.defaultRemovals, isEmpty);
      }
    });

    test('a cropped copy is never preselected', () async {
      photo(original, render(a, width: 4000, height: 3000), size: 4200000);
      photo(r'C:\Users\surya\Pictures\Trip\IMG_1001-crop.jpg',
          render(a, width: 3600, height: 3000, cropX: 0.05), size: 3800000);
      w.scan();
      await analyze();
      for (final g in groups()) {
        expect(g.edited, isTrue, reason: 'aspect ratio changed');
        expect(g.defaultRemovals, isEmpty);
      }
    });

    test('exact duplicates appear once (they belong to the Duplicates tab)',
        () async {
      // Two byte-identical files plus a resized copy.
      final bytes = List<int>.generate(150000, (i) => (i * 13) & 0xFF);
      w.fs
        ..addFile(original, bytes: bytes)
        ..addFile(r'C:\Users\surya\Documents\IMG_1001.jpg', bytes: bytes);
      decoder
        ..add(original, render(a, width: 4000, height: 3000))
        ..add(r'C:\Users\surya\Documents\IMG_1001.jpg',
            render(a, width: 4000, height: 3000));
      photo(r'C:\Users\surya\Downloads\small.jpg',
          render(a, width: 1600, height: 1200, jitter: 0.3, noise: 2));
      w.scan();
      DuplicateFinder(fs: w.fs, db: w.db, clock: w.clock).run(minSize: 1);
      await analyze();
      final g = groups().single;
      expect(g.members, hasLength(2));
    });
  });

  group('safety and robustness', () {
    test('online-only photos are never decoded', () async {
      w.fs.addFile(r'C:\Users\surya\OneDrive - Harbinger\cloud.jpg',
          size: 500000, attrs: const FileAttrs(onlineOnly: true));
      w.scan();
      await analyze();
      expect(decoder.decoded, isEmpty);
    });

    test('small images and HEIC are skipped and counted', () async {
      photo(r'C:\Users\surya\Pictures\icon.png',
          render(a, width: 200, height: 200));
      w.fs.addFile(r'C:\Users\surya\Pictures\x.heic', size: 900000);
      decoder.fail(r'C:\Users\surya\Pictures\x.heic',
          DecodeFailure.unsupportedFormat);
      w.scan();
      final s = await analyze();
      expect(s.tooSmall, 1);
      expect(s.unsupported, 1);
    });

    test('fingerprints are reused on the next run', () async {
      photo(original, render(a, width: 4000, height: 3000));
      w.scan();
      await analyze();
      decoder.decoded.clear();
      w.scan();
      await analyze();
      expect(decoder.decoded, isEmpty);
    });

    group('removal', () {
      late SimilarGroup g;
      setUp(() async {
        photo(original, render(a, width: 4000, height: 3000), size: 4200000);
        photo(r'C:\Users\surya\Downloads\copy.jpg',
            render(a, width: 1600, height: 1200, jitter: 0.15, noise: 2),
            size: 350000);
        w.scan();
        await analyze();
        g = groups().single;
      });

      BatchResult remove(int keepId, Set<int> ids) => removeSimilar(
            [SimilarRemoval(group: g, keepId: keepId, removeIds: ids)],
            db: w.db,
            fs: w.fs,
            trash: w.trash,
          );

      test('the copy goes to the trash; the best photo stays', () {
        final r = remove(g.best.id, g.defaultRemovals);
        expect(r.doneCount, 1);
        expect(w.fs.exists(original), isTrue);
      });

      test('a selection with no kept photo is refused', () {
        final all = {for (final m in g.members) m.id};
        final r = remove(g.best.id, all);
        expect(r.doneCount, 0);
        expect(w.fs.exists(original), isTrue);
      });

      test('if the kept photo disappeared, nothing is removed', () {
        w.fs.externalDelete(original);
        final r = remove(g.best.id, g.defaultRemovals);
        expect(r.doneCount, 0);
        expect(r.skipped.single.reason, SkipReason.keptCopyChanged);
        expect(w.fs.exists(r'C:\Users\surya\Downloads\copy.jpg'), isTrue);
      });
    });
  });

  group('EXIF orientation', () {
    Uint8List jpegWithOrientation(int o, {bool littleEndian = true}) {
      final b = BytesBuilder()
        ..add([0xFF, 0xD8]) // SOI
        ..add([0xFF, 0xE1]); // APP1
      final tiff = BytesBuilder();
      if (littleEndian) {
        tiff
          ..add([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
          ..add([0x01, 0x00]) // 1 entry
          ..add([0x12, 0x01, 0x03, 0x00, 0x01, 0x00, 0x00, 0x00, o, 0x00, 0x00, 0x00]);
      } else {
        tiff
          ..add([0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08])
          ..add([0x00, 0x01])
          ..add([0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, o, 0x00, 0x00]);
      }
      final payload = [...'Exif'.codeUnits, 0, 0, ...tiff.toBytes()];
      final len = payload.length + 2;
      b
        ..add([len >> 8, len & 0xFF])
        ..add(payload)
        ..add([0xFF, 0xD9]);
      return b.toBytes();
    }

    test('reads orientation in both byte orders', () {
      expect(exifOrientation(jpegWithOrientation(6)), 6);
      expect(exifOrientation(jpegWithOrientation(8, littleEndian: false)), 8);
    });

    test('defaults to 1 for non-JPEG or missing EXIF', () {
      expect(exifOrientation(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47])), 1);
      expect(exifOrientation(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9])), 1);
    });
  });
}
