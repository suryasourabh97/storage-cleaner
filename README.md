# Storage Cleaner

A Windows laptop app that safely frees disk space: old files, large files, duplicates, similar photos and app caches. Everything is reviewed before removal, removed files go to a recoverable trash, and nothing is permanently deleted without confirmation.

- Design spec: `.10x/specs/2026-10-07-storage-cleaner-windows-design.md`
- Architecture decisions: `.10x/adrs/`
- Build plan and status: `.10x/decisions/engineering-manager/storage-cleaner.md`, `.10x/status.md`

## Layout

| Path | What |
|------|------|
| `packages/cleaner_core` | Pure Dart engine: scan, index, queries, trash, safety (Milestone 1) |
| `app/` | Flutter Windows app (Milestone 2, not started) |

## Running the core tests

Requires the Dart SDK (3.5+) and SQLite.

```powershell
cd packages\cleaner_core
dart pub get
dart analyze
dart test
```

On Windows, `package:sqlite3` needs `sqlite3.dll` on the PATH or next to the test runner; download the precompiled DLL from sqlite.org if `dart test` reports it missing. On Ubuntu: `sudo apt-get install libsqlite3-dev`.

Safety tests (release blockers) can be run alone with `dart test -t safety`.
