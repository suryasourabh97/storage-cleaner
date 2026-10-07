@TestOn('windows')
library;

// Labelled image set for similar-photo detection (spec §13.6), run through
// the real decoder: real JPEG/PNG encoding, real resizing, real engine
// decoding. Writes distances to calibration_report.txt for CI to publish.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:storage_cleaner/platform/flutter_image_decoder.dart';

class _Blob {
  _Blob(this.cx, this.cy, this.rad, this.r, this.g, this.b);
  final double cx, cy, rad, r, g, b;
}

/// Photo-like scene: gradient background with soft coloured shapes.
class _Scene {
  _Scene(int seed, {double shiftX = 0}) : blobs = _makeBlobs(seed, shiftX);

  static List<_Blob> _makeBlobs(int seed, double shiftX) {
    final rnd = math.Random(seed);
    return [
      for (var k = 0; k < 7; k++)
        _Blob(
          rnd.nextDouble() + shiftX,
          rnd.nextDouble(),
          0.08 + rnd.nextDouble() * 0.15,
          rnd.nextDouble() * 255,
          rnd.nextDouble() * 255,
          rnd.nextDouble() * 255,
        ),
    ];
  }

  final List<_Blob> blobs;

  img.Image render(
    int w,
    int h, {
    double brightness = 1,
    double tintR = 0,
  }) {
    final out = img.Image(width: w, height: h);
    for (var py = 0; py < h; py++) {
      final y = py / h;
      for (var px = 0; px < w; px++) {
        final x = px / w;
        var r = 40 + 120 * x, g = 60 + 100 * y, b = 90 + 60 * (1 - x);
        for (final o in blobs) {
          final d = math.sqrt((x - o.cx) * (x - o.cx) + (y - o.cy) * (y - o.cy));
          final a = (1 - ((d - o.rad) / 0.03)).clamp(0.0, 1.0);
          r = r * (1 - a) + o.r * a;
          g = g * (1 - a) + o.g * a;
          b = b * (1 - a) + o.b * a;
        }
        out.setPixelRgb(
          px,
          py,
          (r * brightness + tintR).clamp(0.0, 255.0).round(),
          (g * brightness).clamp(0.0, 255.0).round(),
          (b * brightness).clamp(0.0, 255.0).round(),
        );
      }
    }
    return out;
  }
}

class _Fp {
  _Fp(this.name, this.image)
      : phash = perceptualHash(image.gray),
        dhash = differenceHash(image.gray);
  final String name;
  final DecodedImage image;
  final int phash;
  final int dhash;
}

void main() {
  testWidgets('labelled set through the real decoder', (tester) async {
    final report = StringBuffer();
    final fps = <String, _Fp>{};

    Future<void> add(String name, Uint8List bytes) async {
      final r = await FlutterImageDecoder.decodeBytes(bytes);
      expect(r, isA<DecodeOk>(), reason: name);
      fps[name] = _Fp(name, (r as DecodeOk).image);
    }

    await tester.runAsync(() async {
      final scene = _Scene(11);
      final base = scene.render(1200, 900);
      await add('original.jpg q92', Uint8List.fromList(img.encodeJpg(base, quality: 92)));
      final small = img.copyResize(base, width: 480, interpolation: img.Interpolation.average);
      await add('resized 480 q60', Uint8List.fromList(img.encodeJpg(small, quality: 60)));
      await add('resized 480 q30', Uint8List.fromList(img.encodeJpg(small, quality: 30)));
      await add('png copy', Uint8List.fromList(img.encodePng(base)));
      await add(
        'filtered (warm)',
        Uint8List.fromList(img.encodeJpg(
          scene.render(1200, 900, brightness: 1.05, tintR: 40),
          quality: 90,
        )),
      );
      final crop = img.copyCrop(base, x: 60, y: 0, width: 1080, height: 900);
      await add('cropped 5% each side', Uint8List.fromList(img.encodeJpg(crop, quality: 90)));
      await add(
        'burst (shapes moved 18%)',
        Uint8List.fromList(img.encodeJpg(_Scene(11, shiftX: 0.18).render(1200, 900), quality: 92)),
      );
      await add(
        'unrelated photo',
        Uint8List.fromList(img.encodeJpg(_Scene(99).render(1200, 900), quality: 92)),
      );
    });

    final o = fps['original.jpg q92']!;
    expect(o.image.width, 1200);
    expect(o.image.height, 900);

    for (final f in fps.values) {
      if (f == o) continue;
      final pd = hamming(o.phash, f.phash);
      final dd = hamming(o.dhash, f.dhash);
      final cd = colorDistance(o.image.colorSig, f.image.colorSig);
      final aspect = f.image.width / f.image.height;
      report.writeln('${f.name}: pHash $pd, dHash $dd, colour '
          '${cd.toStringAsFixed(1)}, ${f.image.width}x${f.image.height} '
          '(aspect ${aspect.toStringAsFixed(3)})');
    }
    File('calibration_report.txt').writeAsStringSync(report.toString());

    const t = SimilarityThresholds();
    bool match(_Fp f) =>
        hamming(o.phash, f.phash) <= t.maxHashDistance &&
        hamming(o.dhash, f.dhash) <= t.maxHashDistance;

    // Positives: same picture, different size/quality/format.
    for (final n in ['resized 480 q60', 'resized 480 q30', 'png copy']) {
      expect(match(fps[n]!), isTrue, reason: '$n should match\n$report');
      expect(colorDistance(o.image.colorSig, fps[n]!.image.colorSig),
          lessThanOrEqualTo(t.maxColorDistance),
          reason: '$n should not look edited\n$report');
    }
    // Negatives: never grouped.
    for (final n in ['burst (shapes moved 18%)', 'unrelated photo']) {
      expect(match(fps[n]!), isFalse, reason: '$n must not match\n$report');
    }
    // Edited copies: if they match, they must be flagged as edited.
    final warm = fps['filtered (warm)']!;
    if (match(warm)) {
      expect(colorDistance(o.image.colorSig, warm.image.colorSig),
          greaterThan(t.maxColorDistance),
          reason: 'filtered copy must be flagged\n$report');
    }
    final cropped = fps['cropped 5% each side']!;
    if (match(cropped)) {
      final la = o.image.width / o.image.height;
      final ca = cropped.image.width / cropped.image.height;
      expect((ca - la).abs() / la, greaterThan(t.maxAspectDifference),
          reason: 'cropped copy must be flagged\n$report');
    }
  });
}
