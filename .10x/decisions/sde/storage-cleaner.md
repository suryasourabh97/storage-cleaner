# SDE — storage-cleaner

## Milestone 1 (core engine) — 2026-10-07

### Built (`packages/cleaner_core`)
| Task | Files |
|------|-------|
| 1.1 skeleton + CI | `pubspec.yaml`, `analysis_options.yaml`, `.github/workflows/core.yml` |
| 1.2 models | `lib/src/model/models.dart`, `path_key.dart` |
| 1.3 platform interface + fake | `lib/src/platform/platform_fs.dart`, `test/fakes/memory_platform_fs.dart` |
| 1.4 PathGuard | `lib/src/safety/path_guard.dart` |
| 1.5 FileMutator + DeletionConfirmation | `lib/src/safety/file_mutator.dart` |
| 1.6 IndexDb | `lib/src/index/index_db.dart` |
| 1.7 Categorizer | `lib/src/scan/categorizer.dart` |
| 1.8 Scanner | `lib/src/scan/scanner.dart` |
| 1.9 old/large queries | `lib/src/query/queries.dart` |
| 1.10 Manifest + README | `lib/src/trash/manifest.dart` |
| 1.11 TrashManager + TrashLocator | `lib/src/trash/trash_manager.dart` |
| 1.12 Reconciler | `lib/src/trash/reconciler.dart` |
| 1.13 PurgeChecker | `lib/src/purge/purge_checker.dart` |
| 1.14 tests | `test/` — 9 files; safety-tagged: guard/mutator, source rules, reconciler drills, purge |

### Verification status
- **Verified in CI (GitHub Actions, ubuntu, Dart stable):** `dart analyze --fatal-infos` clean; **58 tests passed, 26 of them safety-tagged.** First run caught one unused import (fixed).

### Deviations from plan/spec
1. **No folder-mtime skipping on rescan** (spec flow 2). On NTFS a folder's modified time does not change when a file inside it is edited, so skipping would miss size/date changes. Every folder is listed; unchanged rows are cheap upserts. Real speed-up path: NTFS USN change journal (future).
2. **Scan "resume" = restart.** An interrupted scan keeps its partial rows (labelled incomplete via `scan_runs.status`); the next scan re-walks everything. Simpler and correct; acceptable given first-scan target.
3. **`FileAttrs.isLink`** means name-surrogate reparse points only (junction, symlink, mount point). OneDrive placeholders are reparse points too but are not links; the Windows adapter (M2) must classify by reparse tag, or all of OneDrive would be skipped.
4. **Timestamps compared at millisecond precision** (index stores ms; NTFS has 100 ns).
5. **ADR-003:** `package:sqlite3` with hand-written SQL instead of drift.

### Tech debt / follow-ups
- Restored files reappear in Old Files (their date is unchanged). Consider a "keep this file" marker.
- Empty mirror folders are left in the trash after restore/delete.
- Very long mirrored trash paths (> 32k chars) not shortened yet; Windows adapter must use `\\?\` prefixes.
- Drive-letter change for USB drives is handled in manifests (`originalRelative`) but has no test yet (fake can't remap letters).
- `RestoreInto` a folder outside scan roots is rejected by the guard; UI must restrict the folder picker.

## Milestone 2 (Windows app) — 2026-10-07

### Built (`app/`)
| Area | Files |
|------|-------|
| Win32 adapter | `lib/platform/windows/windows_fs.dart` (FindFirstFile listing, reparse-tag classification, no-copy MoveFileEx, leaf FFI error codes), `system_info.dart` (known folders, OneDrive roots, drives, disk space) |
| Services | `lib/services/app_controller.dart` (engine wiring, launch reconciliation), `scan_worker.dart` (isolate scan, shared-memory cancel), `settings.dart` |
| UI | `lib/main.dart`, `lib/ui/home_page.dart`, `files_page.dart` (old + large), `trash_page.dart`, `settings_page.dart`, `widgets/confirm_dialogs.dart`, `format.dart` |
| CI | `.github/workflows/app.yml` (windows-latest: generate runner, analyze, test, build, upload exe) |

### Verification
- Windows CI: analyze clean; **15 app tests passed** on real NTFS; release build succeeded and uploaded.
- Bug found by CI and fixed: `GetLastError` returned 0 after ordinary FFI calls (runtime clobbers last-error) → missing files reported as I/O errors. Fixed with leaf bindings + type-check fallback.

### Deviations
- Riverpod replaced by `ChangeNotifier` (see senior-engineer M2 notes).
- Windows runner is generated in CI by `flutter create` (not committed) until M6 needs runner changes.
- OneDrive files are listed but not selectable until M5 (Free up space).
- Old/large queries and trash moves run on the UI isolate; fine for typical sizes, may stutter on very large result sets (> ~100k rows). Move to isolate if it shows in testing.
- No onboarding screen yet; scheduled-task reminder is M6 (banner on Home covers purge-ready items meanwhile).
- `index.db` lives in `%LOCALAPPDATA%\StorageCleaner`; settings in `%APPDATA%\StorageCleaner\settings.json`.

### Tech debt
- File IDs not read during scan (needed in M3 for hard links).
- No widget tests for screens yet (only logic + real-FS tests).

## Milestone 3 (exact duplicates) + redesign — 2026-10-07

### Built
- Core `lib/src/duplicates/`: `ContentHasher` (sample = first/middle/last 64 KB + size; full = chunked SHA-256), `DuplicateFinder` (size → hard-link collapse via lazily fetched NTFS file IDs → sample → full; stat re-check before and after hashing; cancellable; hashes persisted so runs resume and repeat runs read nothing), `KeepRules` (OneDrive > Documents/Pictures/Desktop/Videos/Music > other > Downloads/temp-like; then oldest, shortest path), `duplicateGroups()` query, `removeDuplicates()` (refuses selections without a kept copy; skips the whole group if the kept copy is gone, changed or re-hashed differently).
- `PlatformFs` gained `readRange` and `fileIdOf`; Windows: `RandomAccessFile` reads, `CreateFileW(FILE_READ_ATTRIBUTES)` + `GetFileInformationByHandle`.
- Index: `duplicateCandidates`, `fullHashMatches`, hash setters, analysis runs; upsert keeps file IDs while size/mtime are unchanged.
- App: background analysis isolate (shared cancel flag), Duplicates screen (keep/remove per group, "Keep this one"), duplicate min-size setting, overview counts duplicates in reclaimable space.
- Redesign: `lib/ui/theme.dart` tokens + `ThemeExtension`, `widgets/components.dart`, `widgets/storage_bar.dart`, sidebar shell, all screens rebuilt; copy rewritten (no middle-dot meta strings).
- Screenshot pipeline: `app/test_screenshots/` renders all screens on a demo profile with real Segoe UI fonts; CI pushes PNGs to branch `ci-screenshots` (artifact storage is unreachable from the cloud workspace; git is).

### Verification
- Core: 76 tests passed (42 safety) — first run. App: 20 tests passed (incl. component/theme widget tests in light and dark). Visual review of CI screenshots found and fixed: dropdown text not inheriting the app font; kept duplicate looked disabled.

### Deviations
- Full hashing uses `package:crypto` SHA-256 in Dart instead of Windows CNG (ADR-004 said CNG). Simpler and portable; revisit if hashing throughput is a problem in hands-on testing.
- "Find duplicates" is a separate action (not automatic after scan), as specified.

### Tech debt
- Duplicate removal and trash moves still run on the UI isolate.
- Screenshot demo uses `C:\ScreenshotDemo` on the CI runner; not part of the product.
