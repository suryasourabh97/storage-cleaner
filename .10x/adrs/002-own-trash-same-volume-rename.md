# ADR-002: Own per-drive trash using same-volume rename and manifests

**Status:** Accepted
**Date:** 2026-10-07
**Feature:** storage-cleaner
**Author:** 10x-Team (Architect + Staff Engineer)

## Context
Removed files must be recoverable for 30 days, never purged without confirmation, survive uninstall and index loss, and work on USB drives. The Windows Recycle Bin can silently delete oversize files, is missing on many removable drives, and can be auto-emptied by Storage Sense.

## Decision
- Trash root: `%USERPROFILE%\StorageCleaner Trash` on the system drive; `X:\StorageCleaner Trash` on other drives. A file is only ever trashed on its own volume (compared by volume serial).
- Move = `MoveFileExW` **without** `MOVEFILE_COPY_ALLOWED`. If it fails, the file is skipped; there is no copy fallback.
- Trash mirrors the original path relative to its scan root (`Downloads\report.pdf`), suffixing collisions.
- Each trash root holds `README.txt` and `manifest.json` (written atomically: temp file + rename). The manifest is the durable source of truth; the SQLite index is a cache that can be rebuilt from it.
- Two-phase state per item in the index (`moving` → `trashed`), reconciled on launch by checking which path exists.

## Alternatives Considered
| Alternative | Pros | Cons | Why Not |
|-------------|------|------|---------|
| Windows Recycle Bin | Familiar, native restore | Oversize = permanent, no bin on many USB drives, Storage Sense auto-empty | Violates confirmation and recoverability guarantees |
| Single trash folder in `%LOCALAPPDATA%` | One place | Cross-volume moves become copies (slow, partial-failure risk); deleted on some uninstalls | Copies break instant, atomic move |
| Hidden trash folder | Less clutter | Hard to recover without the app | User required recoverability after uninstall |

## Consequences
### Positive
- Atomic, instant moves; files recoverable by hand; survives uninstall.
### Negative
- Trash folders visible in user profile and drive roots.
- Manifest write per batch adds I/O.
### Risks
- Manifest/index divergence after crashes → launch-time reconciliation and manifest-first rebuild, covered by failure drills.

## Dependencies
- ADR-006 (all deletes through the guarded deleter). Constrains restore and purge flows.
