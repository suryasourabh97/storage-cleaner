# ADR-007: Decode photos with Flutter's engine codecs for similar-photo fingerprints

**Status:** Accepted (amends the decoder choice in ADR-004)
**Date:** 2026-10-07
**Feature:** storage-cleaner
**Author:** 10x-Team (Architect + Staff Engineer)

## Context
Similar-photo detection needs a small, correctly rotated rendition of each photo plus its full dimensions. ADR-004 named the Windows Imaging Component (WIC). WIC is COM-based; calling it from Dart FFI means hand-written vtable bindings for several interfaces, verified only through CI. The target is ~20,000 photos in ≤ 5 minutes.

## Decision
- Core defines `ImageDecoder` (async) returning `DecodedImage` (dimensions after EXIF orientation, 64×64 grayscale, 4×4 RGB colour signature) or a typed failure. Perceptual hashing (pHash via separable DCT on 32×32, dHash on 9×8), matching and grouping stay in pure Dart in `cleaner_core`.
- The app implements the decoder with Flutter's engine codecs: `ImageDescriptor.encoded` for dimensions, `instantiateCodec(targetWidth: 64, targetHeight: 64)` for a scaled decode (JPEG uses decode-time downscaling), EXIF orientation read by a small pure-Dart parser to correct dimensions.
- The similar-photo pass runs asynchronously on the UI isolate (decoding happens on engine threads); duplicates still run in their own isolate.
- HEIC/HEIF are reported as "not supported yet" (Skia has no HEIC codec). RAW and video stay out of scope (spec).

## Alternatives Considered
| Alternative | Pros | Cons | Why Not |
|-------------|------|------|---------|
| WIC via FFI (ADR-004) | HEIC with the Microsoft extension, very fast scaled decode | Many COM interfaces bound by hand, high blind-integration risk | Risk/time; can be added later behind the same interface |
| Windows shell thumbnails (IShellItemImageFactory) | Uses thumbnail cache, HEIC support | COM again; thumbnails vary in source/size; no reliable full dimensions | Same COM risk, less predictable input |
| `package:image` (pure Dart) | Runs in any isolate, testable everywhere | Full-resolution decode in Dart: ~0.5–1 s per 12 MP JPEG | Far too slow for the target |

## Consequences
### Positive
- No new native bindings; works in CI widget tests on Windows with real JPEG/PNG files.
### Negative
- HEIC photos are skipped (reported with a count).
- Fingerprinting shares the UI isolate's event loop (async; decoding itself is off-thread).
### Risks
- Engine decoder behaviour (orientation, colour management) differs from WIC → calibration tests run on real encoded images in Windows CI.

## Dependencies
- ADR-004 pipeline shape unchanged (exact-duplicate collapse, bucketed matching, star grouping, edited flag).
