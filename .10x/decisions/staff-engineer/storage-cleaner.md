# Staff Engineer — storage-cleaner

**Date:** 2026-10-07

## Standards
- Dart 3.x, null safety, `package:lints/recommended` + `strict-casts`, `strict-raw-types`.
- `cleaner_core` must not import `package:flutter` or `package:win32` (enforced by a test that scans imports).
- Only `lib/src/safety/file_mutator.dart` may call `PlatformFs.move/delete/dehydrate` (enforced by a source-scan test).
- Errors: expected per-file failures are values (`OpOutcome` sealed class: `done`, `skipped(reason)`); exceptions only for programmer errors and fatal I/O.
- Paths: always absolute, normalized, compared case-insensitively on Windows (`PathKey`). Long paths prefixed `\\?\` only inside the Windows adapter.
- Time: inject `Clock`; never call `DateTime.now()` in core.
- Logging: local rotating log at `%LOCALAPPDATA%\StorageCleaner\logs`; no file contents, no telemetry.

## Cross-cutting concerns
- Cancellation: every long operation takes a `CancelToken`, checked per file/batch.
- Progress: `Stream<Progress>` with counts and bytes.
- Batching: index writes 1,000 rows per transaction; manifest flush per batch.

## Reuse
- `package:path` (windows context), `package:crypto` (tests), `package:image` (test decoder), `package:sqlite3`, `package:win32`, `package:ffi`, `flutter_riverpod`.

## Testing conventions
- `test/fakes/memory_platform_fs.dart`: in-memory volumes, attributes, reparse points, locks, file IDs — the backbone of core tests.
- Safety tests tagged `@Tags(['safety'])`; CI fails if any is skipped.

## Visual system (2026-10-07)
- Tokens live in `app/lib/ui/theme.dart` (`Tokens` ThemeExtension); screens never hard-code colors.
- Amber is reserved for "reclaimable" (capacity-bar hatching, selected-row marker, primary reclaim action); brick red only for permanent deletion.
- Sizes always use tabular figures. Large figures: Segoe UI Variable Display, light weight.
- Copy: sentence case, plain verbs, no all-caps labels, no middle-dot meta strings.
- Any UI change must be reviewed via the CI screenshots (`ci-screenshots` branch) before it ships.
