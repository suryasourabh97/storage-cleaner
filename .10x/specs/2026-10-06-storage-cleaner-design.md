# Storage Cleaner — Design Spec

**Feature slug:** `storage-cleaner`
**Date:** 2026-10-06
**Status:** Awaiting user review
**Author:** 10x-Team (brainstorming, all roles) with Surya Modekurti

---

## 1. Summary

An Android app that frees storage space in two ways:

1. **Old files** — finds files in shared storage not modified for longer than a user-chosen threshold, lets the user review them by category, and moves the selected ones to a recoverable trash.
2. **App cache** — shows installed apps ranked by cache size and clears caches through Android's own system prompts.

Nothing is ever deleted without explicit user confirmation, and trashed files survive an accidental uninstall.

## 2. Scope

### In scope (v1)
- Android 8.0 (API 26) and above
- Old-file scanning, review, trash, restore, confirmed permanent deletion
- App-cache listing and clearing via system prompts
- Uninstall-safe trash

### Out of scope (v1)
- **iOS.** The Flutter codebase stays iOS-ready; a later release is expected to cover old photos/videos via the Photos library only, since iOS does not allow scanning general files or other apps' caches.
- Automatic (unreviewed) cleanup
- Per-category age thresholds
- Duplicate-file detection, large-file finder independent of age
- Accessibility-service automation of cache clearing (Play Store policy risk, brittle across phone brands)

## 3. Key decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Platform | Android only for v1; iOS deferred |
| D2 | Framework | Flutter (Dart), with a small Kotlin layer via platform channels |
| D3 | Deletion model | Review → confirm → move to trash → permanent delete only after a second confirmation |
| D4 | Trash retention | Items become purge-eligible after 30 days; user is notified and must confirm. Ignored items stay in trash |
| D5 | Cache clearing | Android 11+: system "clear all caches" prompt. All versions: per-app shortcut to the app's storage settings. Android 8–10: per-app only |
| D6 | "Untouched" definition | File last-modified time older than threshold (last-access time is unreliable on Android filesystems) |
| D7 | Threshold | User picks 3 months / 6 months / 1 year / 2 years; default 6 months |
| D8 | Scan scope | All readable shared storage; camera media shown but unselected by default; hidden folders skipped; user-managed exclusion list |
| D9 | Architecture | Scan in Dart (background isolate) into a local SQLite index; Kotlin only for what Dart cannot do |
| D10 | Trash mechanism | Same-volume rename into a visible per-volume trash folder that mirrors original paths |

## 4. Permissions

| Permission | Why | When requested | If denied |
|-----------|-----|----------------|-----------|
| All files access (`MANAGE_EXTERNAL_STORAGE`) | Scan and move files across shared storage | First launch, after an explanation screen | Scan and trash actions disabled; banner with "Grant access" |
| Usage access (`PACKAGE_USAGE_STATS`) | Read per-app cache sizes | First visit to App Cache screen | App Cache screen shows explanation and settings button; rest of app works |
| Notifications (`POST_NOTIFICATIONS`, Android 13+) | Purge-ready notifications | First time an item is trashed | No notification; purge check still runs on app open |

On Android 8–10, broad storage access uses `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` (with `requestLegacyExternalStorage` on Android 10).

**Play Store:** `MANAGE_EXTERNAL_STORAGE` requires a policy declaration. File management is the app's core purpose, which is a permitted use, but approval must be obtained before launch.

## 5. Architecture

### 5.1 Screens (Flutter UI)

| Screen | Contents |
|--------|----------|
| Home | Storage used, space held by old files, total app cache, Scan button with progress |
| Old Files | Results grouped by category (Downloads, Documents, Videos, Audio, Installers, Messaging media, Camera, Other), sorted by size; select and "Move to trash" |
| App Cache | Apps ranked by cache size; "Clean all"; tap an app to open its storage settings |
| Trash | Trashed files with original location and days remaining; Restore, Delete now, Empty trash |
| Settings | Age threshold, excluded folders, permission status, "Empty all trash before uninstalling" |

### 5.2 Core logic (pure Dart)

All file access goes through `package:file` so this layer runs against an in-memory filesystem in tests.

- **Scanner** — walks shared storage in a background isolate; skips hidden folders, excluded folders, and trash folders; never follows symbolic links; writes to the index in batches; reports progress.
- **File index** — SQLite database (via `drift`) of scanned files: path, size, last-modified, category, volume, state.
- **Categorizer** — assigns category from extension and folder; marks camera media (`DCIM/`) as protected (unselected by default).
- **Trash manager** — moves, restores, and permanently deletes files; maintains per-volume manifests; reconciles interrupted moves.

### 5.3 Android bridge (Kotlin)

Typed platform channels (generated with `pigeon`):

- **Permissions** — check and request all-files, usage, and notification access.
- **App cache** — list installed apps with cache size (`StorageStatsManager.queryStatsForPackage`); launch the system clear-all-caches prompt (`StorageManager.ACTION_CLEAR_APP_CACHE`, Android 11+); open per-app settings (`Settings.ACTION_APPLICATION_DETAILS_SETTINGS`).
- **Quick estimate** — query `MediaStore` for an instant approximate total while the full scan runs.
- **Volumes** — list mounted storage volumes and their roots.

### 5.4 Background job

- **Daily purge check** (WorkManager via the `workmanager` package) — finds trash items older than 30 days and posts one summary notification. **It never deletes.** The same check also runs whenever the app opens, in case the phone's battery saver delays the job.

### 5.5 State management

Riverpod for UI state, with the core logic exposed as providers.

## 6. Data model

### `files` table
| Column | Notes |
|--------|-------|
| `id` | Primary key |
| `path` | Current absolute path (unique) |
| `original_path` | Set when trashed |
| `volume_id` | Which storage volume |
| `size_bytes` | |
| `modified_at` | Filesystem last-modified time |
| `category` | Enum |
| `protected` | True for camera media |
| `state` | `indexed`, `moving`, `trashed`, `restoring`, `deleting` |
| `trashed_at` | Set when trashed |

### `folders` table
Each scanned folder's path and last-modified time, used to skip unchanged folders on rescan.

### `scan_runs` table
Start time, end time, status (`running`, `complete`, `interrupted`), counts of files and skipped folders. Used to offer resume after an interruption and to label results "incomplete".

### `exclusions` table
User-excluded folder paths.

Indexes: `(state, modified_at)` for the Old Files query; `(state, trashed_at)` for the purge check; unique on `path`.

## 7. Trash design (uninstall-safe)

- **Location:** a visible folder named `StorageCleaner Trash` at the root of each storage volume. A file is always trashed on its own volume, so moving is an instant rename, never a copy.
- **Structure mirrors the original path**, keeping original filenames: `Download/report.pdf` → `StorageCleaner Trash/Download/report.pdf`. Name collisions get a numeric suffix (`report (1).pdf`).
- **`.nomedia`** in each trash folder keeps trashed media out of the gallery.
- **`README.txt`** in each trash folder explains what it is and how to recover files manually with any file manager.
- **`manifest.json`** in each trash folder records, for every item, the trash path, original path, size, and trash date. It is updated after every trash, restore, and delete.

### Surviving uninstall and data loss
- Trash folders live in shared storage, so Android does not remove them when the app is uninstalled.
- On reinstall or after "Clear data", the app finds existing trash folders and rebuilds the trash list from their manifests, so restore keeps working.
- Settings (threshold, exclusions) are included in Android Auto Backup and restored on reinstall. The scan index is excluded since a rescan rebuilds it.
- The manifest declares `android:hasFragileUserData="true"`, so on Android 10+ the uninstall dialog offers to keep the app's data.
- Android provides no hook before uninstall, so the app cannot warn at that moment. Onboarding explains that trash survives uninstall, and Settings offers "Empty all trash" for users who want it gone.

## 8. Data flows

1. **First launch** — explanation screen → All files access. Usage access and notification permission are requested later, when first needed.
2. **Scan** — show `MediaStore` quick estimate → background walk writes to index in batches with live progress → mark scan complete. Rescans skip folders whose modified time is unchanged and remove index entries for files that no longer exist.
3. **Review** — query index for `state = indexed`, older than threshold, not excluded; group by category. Camera media unselected. Changing the threshold re-runs the query only.
4. **Move to trash** — user selects → confirmation dialog ("Move 142 files (3.8 GB) to trash?" with expandable list) → for each file: re-check it exists and is unchanged → mark `moving` → rename → update manifest → mark `trashed`. Summary reports moved and skipped counts.
5. **Restore** — mark `restoring` → recreate original folder if missing → rename back → on name conflict, user chooses "keep both" (suffix) or a different folder → update manifest → mark `indexed`.
6. **Purge** — daily check finds items more than 30 days in trash → one notification ("12 files (1.1 GB) ready to delete permanently") → tapping opens Trash with those preselected → strong confirmation → permanent delete.
7. **Delete now / Empty trash** — strong confirmation ("This can't be undone", red non-default button) → permanent delete → update manifest.
8. **App cache** — read sizes via bridge → ranked list → "Clean all" opens Android's system prompt (Android's own confirmation) → on return, re-read sizes and show space freed. Per-app tap opens that app's storage settings.

## 9. Confirmation rules

| Action | Confirmation |
|--------|-------------|
| Move to trash | Dialog with count, total size, expandable file list |
| Restore | None needed (non-destructive) |
| Delete now / Empty trash / Purge | Strong warning, explicitly irreversible, red non-default button |
| Clean all caches | Android system prompt |
| Clear one app's cache | User taps "Clear cache" in system settings |
| Background job | Never deletes; notification only |

## 10. Error handling

| Situation | Behavior |
|-----------|----------|
| All files access revoked | Checked on every app resume; scan and trash actions disabled; banner to re-grant; trash list remains visible |
| Usage access denied | Only App Cache screen affected; explanation and settings button |
| Scan interrupted | Batched writes keep partial results; next launch offers resume or restart; results labeled "incomplete" until complete |
| File deleted since scan | Skipped silently; index entry removed |
| File modified since scan | Skipped; reported in summary ("3 skipped — changed since scan") |
| Crash mid-move | `moving` rows reconciled on next launch by checking which path exists; manifest and index corrected |
| Rename fails (read-only folder, etc.) | File skipped and reported; **no copy-then-delete fallback** |
| SD card removed | Its trash items shown as "unavailable", excluded from purge, return when card is reinserted |
| App data cleared / reinstall | Trash rebuilt from manifests |
| Original folder gone on restore | Folder recreated |
| Name conflict on restore | User chooses keep both or another folder |
| Background job delayed | Purge check also runs on app open; nothing is deleted without confirmation anyway |
| Symbolic links | Never followed |
| Unreadable folders | Skipped and counted in scan summary |

## 11. Testing strategy

1. **Unit tests (Dart, in-memory filesystem)** — categorizer, age filtering, exclusion matching, camera-media default, trash state transitions and crash reconciliation, manifest write and rebuild, restore conflicts and folder recreation.
2. **Safety tests (release blockers)**
   - Permanent deletion reachable only through the single confirmed delete path; a test asserts no other code calls delete.
   - Excluded folders and trash folders are never scanned or moved.
   - Files changed after the scan are never trashed.
3. **Device tests (emulators)** — Android 8, 10, 11, 13, 15: permission grant/revoke, system cache prompt and per-app settings intents, real renames, emulated SD card remove/reinsert.
4. **Failure drills (scripted)** — kill app mid-move; revoke access mid-session; clear app data → trash rebuilt; **uninstall and reinstall → every trashed file present and restorable**.
5. **Performance** — 100,000-file fixture. Targets: first scan ≤ 60 s on a mid-range phone; rescan substantially faster via folder skipping; no dropped UI frames during scan.
6. **Manual device matrix** — Samsung, Xiaomi, Pixel at minimum (settings-screen differences, aggressive battery management).
7. **Pre-launch** — Play Store "All files access" declaration approved.

## 12. Success criteria

- A user can scan, review, and reclaim space from old files in under 2 minutes on first use.
- Zero files permanently deleted without an explicit confirmation (enforced by safety tests).
- Every trashed file is restorable after a crash, a data clear, or an uninstall and reinstall (enforced by failure drills).
- Play Store approval for All files access obtained.

## 13. Risks

| Risk | Mitigation |
|------|-----------|
| Play Store rejects All files access declaration | Core purpose is file management (permitted category); prepare clear declaration and demo video early; fallback is a reduced app using the Storage Access Framework folder picker |
| Last-modified time flags files the user still opens | Review step, camera media unselected by default, 30-day trash, restore |
| Trash folders left behind after uninstall consume space | Explained in onboarding and README.txt; "Empty all trash" in Settings |
| System clear-all-caches prompt behaves differently on some phone brands | Per-app shortcuts always available; covered in manual device matrix |
| First scan slow on large storage | Quick `MediaStore` estimate shown immediately; background isolate; rescans skip unchanged folders |

## 14. Future work (not v1)

- iOS release: old photos/videos via the Photos library (deletions go to iOS "Recently Deleted").
- Per-category thresholds.
- Scheduled automatic scans with review-ready notifications.
