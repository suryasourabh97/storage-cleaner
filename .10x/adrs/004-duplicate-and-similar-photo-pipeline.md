# ADR-004: Staged duplicate pipeline and perceptual-hash similar-photo matching

**Status:** Accepted
**Date:** 2026-10-07
**Feature:** storage-cleaner
**Author:** 10x-Team (Architect + Staff Engineer)

## Context
Exact duplicates require reading contents; similar photos require decoding images. Both must be fast, cancellable, resumable, never read online-only OneDrive files, never report hard links, and never remove a last copy.

## Decision
- **Duplicates:** candidates (≥ min size, local) → group by exact size → collapse same NTFS file ID → sample hash (first/middle/last 64 KB) → full SHA-256. Hashes cached with (size, mtime).
- **Similar photos:** exact-duplicate sets collapsed first → decode at reduced size (WIC on Windows; pure-Dart `package:image` in tests behind the `ImageDecoder` interface) → EXIF orientation → 64-bit pHash (DCT 32×32→8×8) + 64-bit dHash → match only if both within strict Hamming threshold (initial 4) → candidate pairs via 8-bucket pigeonhole index → star grouping (member must match the group's kept photo) → edited flag if aspect ratio differs > 1% or color signature distance exceeds threshold.
- Keep rules and the at-least-one-copy invariant live in a single `KeepRuleEngine`; selections are validated there, not in UI code.
- Hashing behind `Hasher` interface: Windows CNG in app, `package:crypto` in tests.

## Alternatives Considered
| Alternative | Pros | Cons | Why Not |
|-------------|------|------|---------|
| Full hash of every file | Simple | Reads the whole disk | Far too slow |
| Name + size duplicates | No reads | False positives | User chose identical content |
| ML embeddings for similarity | Robust | Model size, compute, opaque | Overkill for near-identical copies |
| Union-find grouping | Standard | Chains A≈B≈C into unrelated photos | Star grouping is stricter |

## Consequences
### Positive
- Most files never read; repeat runs near-instant.
### Negative
- Threshold needs calibration on a labelled image set.
### Risks
- pHash weak on heavy crops → crops are flagged as edited (not auto-removed) anyway.

## Dependencies
- ADR-003 (hash cache columns), ADR-006 (removal via guarded trash).
