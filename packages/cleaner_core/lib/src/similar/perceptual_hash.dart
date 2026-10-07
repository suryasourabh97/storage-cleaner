import 'dart:math' as math;
import 'dart:typed_data';

import 'image_decoder.dart';

/// Averages a square or rectangular grayscale image down to [dw]×[dh]; each
/// source pixel contributes to exactly one target cell.
Float64List downsample(Uint8List src, int sw, int sh, int dw, int dh) {
  final sum = Float64List(dw * dh);
  final count = Int32List(dw * dh);
  for (var y = 0; y < sh; y++) {
    final ty = y * dh ~/ sh;
    for (var x = 0; x < sw; x++) {
      final tx = x * dw ~/ sw;
      sum[ty * dw + tx] += src[y * sw + x];
      count[ty * dw + tx]++;
    }
  }
  for (var i = 0; i < sum.length; i++) {
    if (count[i] > 0) sum[i] /= count[i];
  }
  return sum;
}

final List<Float64List> _cos = [
  for (var u = 0; u < 8; u++)
    Float64List.fromList([
      for (var x = 0; x < 32; x++) math.cos((2 * x + 1) * u * math.pi / 64),
    ]),
];

/// 64-bit perceptual hash: DCT of the 32×32 rendition, top-left 8×8
/// frequencies, each bit = coefficient above the median (DC excluded from
/// the median).
int perceptualHash(Uint8List gray) {
  const s = fingerprintSide;
  final g = downsample(gray, s, s, 32, 32);
  // Separable DCT-II, only the 8 lowest frequencies in each direction.
  final rows = Float64List(32 * 8);
  for (var y = 0; y < 32; y++) {
    for (var u = 0; u < 8; u++) {
      var acc = 0.0;
      final c = _cos[u];
      for (var x = 0; x < 32; x++) {
        acc += g[y * 32 + x] * c[x];
      }
      rows[y * 8 + u] = acc;
    }
  }
  final coef = Float64List(64);
  for (var v = 0; v < 8; v++) {
    final c = _cos[v];
    for (var u = 0; u < 8; u++) {
      var acc = 0.0;
      for (var y = 0; y < 32; y++) {
        acc += rows[y * 8 + u] * c[y];
      }
      coef[v * 8 + u] = acc;
    }
  }
  final sorted = Float64List.fromList(coef.sublist(1))..sort();
  final median = (sorted[31] + sorted[32]) / 2;
  var hash = 0;
  for (var i = 0; i < 64; i++) {
    if (coef[i] > median) hash |= 1 << i;
  }
  return hash;
}

/// 64-bit difference hash: 9×8 rendition, each bit = left brighter than
/// right neighbour.
int differenceHash(Uint8List gray) {
  const s = fingerprintSide;
  final g = downsample(gray, s, s, 9, 8);
  var hash = 0;
  var bit = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      if (g[y * 9 + x] > g[y * 9 + x + 1]) hash |= 1 << bit;
      bit++;
    }
  }
  return hash;
}

/// Number of differing bits.
int hamming(int a, int b) {
  var x = a ^ b;
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}

/// Mean absolute difference of two colour signatures (0–255).
double colorDistance(Uint8List a, Uint8List b) {
  if (a.length != b.length || a.isEmpty) return 255;
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]).abs();
  }
  return sum / a.length;
}
