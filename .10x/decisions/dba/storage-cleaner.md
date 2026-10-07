# DBA — storage-cleaner

## Schema v1 (`PRAGMA user_version = 1`)
- `files` — one row per known file. `path_key` (lower-cased normalized path) is UNIQUE; it moves with the file when trashed/restored. Hash and fingerprint columns exist from v1 so M3/M4 need no migration.
- `scan_runs`, `exclusions`, `analysis_runs`, `cache_runs` as spec §6. (`folders` table dropped — see SDE deviation 1.)

## Indexes
| Index | Serves |
|-------|--------|
| `files(state, modified_at)` | Old Files |
| `files(state, size_bytes)` | Large Files, duplicate candidates |
| `files(state, trashed_at)` | Purge check |
| `files(size_bytes, full_hash)` | Duplicate grouping (M3) |
| UNIQUE `path_key` | Upsert target, lookups |

## Write patterns
- Scanner upserts in 1,000-row transactions with a prepared statement. Upsert only touches `state = 'indexed'` rows, so trashed/in-flight rows are never overwritten by a scan. Hashes/fingerprints are cleared when size or mtime changes.
- `deleteUnseen` runs only after a complete scan, only for `indexed` rows under scanned roots, using `substr` prefix match (no LIKE-escaping pitfalls).
- WAL mode for file databases.

## Durability
- The index is a cache. Trash truth = per-drive `manifest.json` (atomic temp-then-replace writes). `Reconciler` rebuilds trash rows from manifests and repairs manifests from rows.

## Migrations
- Forward-only via `user_version`; opening a newer schema throws (prevents an older app from corrupting a newer index).
