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
- **Syntax:** all 22 Dart files parse cleanly (tree-sitter Dart grammar).
- **Not yet run:** `dart analyze` and `dart test`. The cloud workspace cannot download the Dart SDK. Must run on the user's machine or CI before M1 is marked verified.

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
