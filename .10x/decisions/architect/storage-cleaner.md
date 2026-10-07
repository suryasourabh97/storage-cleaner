# Principal Architect — storage-cleaner

**Date:** 2026-10-07
**ADRs:** 001–006

## Repository layout
```
storage-cleaner/
├── packages/cleaner_core/        # pure Dart, no Flutter, no Win32 (ADR-001)
│   ├── lib/src/
│   │   ├── model/                # FileEntry, Category, ItemState, groups
│   │   ├── platform/             # interfaces: PlatformFs, Hasher, ImageDecoder, ProcessLister, Clock
│   │   ├── safety/               # PathGuard, FileMutator, DeletionConfirmation (ADR-006)
│   │   ├── index/                # IndexDb (sqlite3), migrations (ADR-003)
│   │   ├── scan/                 # Scanner, Categorizer, ScanRoots
│   │   ├── query/                # OldFilesQuery, LargeFilesQuery
│   │   ├── trash/                # TrashManager, Manifest, Reconciler (ADR-002)
│   │   ├── duplicates/           # DuplicateFinder (ADR-004)
│   │   ├── similar/              # PerceptualHash, SimilarPhotoFinder (ADR-004)
│   │   ├── keep/                 # KeepRuleEngine
│   │   ├── cache/                # CacheCatalog, CacheCleaner
│   │   ├── onedrive/             # FreeUpSpace
│   │   └── purge/                # PurgeChecker (ADR-005)
│   └── test/                     # fakes + unit/safety tests
└── app/                          # Flutter Windows app
    ├── lib/platform/windows/     # FFI implementations of core interfaces
    ├── lib/ui/                   # screens (Riverpod)
    ├── assets/cache_catalog.json
    └── windows/runner/           # hidden --purge-check mode (ADR-005)
```

## Boundaries
- UI → application services (Riverpod providers) → `cleaner_core` → platform interfaces.
- Only `FileMutator` changes user files (ADR-006). Scanner, finders and queries are read-only.
- Long work (scan, analyze) runs in a background isolate; the isolate opens its own SQLite connection; progress events flow back over a `SendPort` stream.

## Key interfaces (core)
- `PlatformFs`: `list(dir)` → entries with name, size, mtime, attributes {directory, reparsePoint, hidden, system, onlineOnly, pinned}, fileId, volumeSerial; `move(from,to)` (no copy); `delete(path)`; `dehydrate(path)`; `exists`, `stat`; `readRange(path, offset, len)`; `openRead(path)`.
- `Hasher`: `sha256(stream)`, `sample(path)`.
- `ImageDecoder`: `decode(path)` → {width, height (oriented), gray32x32, gray9x8, colorSig}.

## Failure modes (design-level)
| Failure | Containment |
|---------|-------------|
| Crash mid-move | Two-phase index state + manifest reconciliation on launch |
| Index corruption | Delete and rebuild: manifests for trash, rescan for files |
| Volume missing | Items marked unavailable; never purged |
| Guard rejection | Reported per file; operation continues for others |
| Isolate crash during scan/analyze | Run marked interrupted; resume next time |

## Data model
Spec §6, plus ADR-003 choices (sqlite3, user_version migrations).
