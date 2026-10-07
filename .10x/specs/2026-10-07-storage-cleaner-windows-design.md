# Storage Cleaner for Windows — Design Spec

**Feature slug:** `storage-cleaner`
**Date:** 2026-10-07
**Status:** Awaiting user review (updated 2026-10-07 with duplicate, large-file and similar-photo finders)
**Supersedes:** `2026-10-06-storage-cleaner-design.md` (Android version — retained as a possible later release)
**Author:** 10x-Team (brainstorming, all roles) with Surya Modekurti

---

## 1. Summary

A Windows laptop app that frees disk space in five ways:

1. **Old files** — finds files in the user's folders and data drives not modified for longer than a user-chosen threshold, lets the user review them by category, and either moves them to a recoverable trash or, for OneDrive files, frees the local copy while keeping the file in the cloud.
2. **Large files** — lists files above a user-chosen size, whatever their age.
3. **Duplicate files** — finds files with identical content, preselects the extra copies using a "best copy" rule, and always keeps at least one copy.
4. **Similar photos** — finds near-identical copies of the same photo (resized, re-compressed, converted, lightly edited), keeps the highest-quality copy, and leaves groups containing edited versions for the user to decide.
5. **App cache** — finds cache folders of common apps in the current user's account, shows their sizes, and clears them after confirmation.

Nothing is ever permanently deleted without explicit user confirmation, and trashed files survive an accidental uninstall.

## 2. Scope

### In scope (v1)
- Windows 10 (22H2) and Windows 11, x64
- Runs under a standard (non-admin) user account; installs per-user without admin rights
- Old-file scanning, review, trash, restore, confirmed permanent deletion
- Large-file finder (any age)
- Duplicate-file finder (identical content)
- Similar-photo finder (near-identical copies)
- OneDrive "Free up space" for old synced files
- User-level app-cache cleaning from a curated list
- Uninstall-safe trash
- Daily background reminder for trash items ready to delete

### Out of scope (v1)
- macOS, Linux, Android, iOS (Android design is preserved in the superseded spec for a later release)
- Admin-level cleanup (Windows Update cache, `C:\Windows\Temp`, crash dumps, Delivery Optimization)
- Other users' accounts on the same laptop
- Network drives
- Automatic (unreviewed) cleanup
- Per-category age thresholds
- Burst/series-shot grouping and adjustable similarity sensitivity
- RAW camera formats and video similarity
- Using the Windows Recycle Bin as the trash

## 3. Key decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Platform | Windows only for v1 (replaces Android) |
| D2 | Framework | Flutter (Dart) desktop; Windows APIs called from Dart via FFI (`package:win32`), plus small edits to the Flutter Windows runner |
| D3 | Deletion model | Review → confirm → move to trash → permanent delete only after a second confirmation |
| D4 | Trash | App's own `StorageCleaner Trash` folder per drive, not the Recycle Bin |
| D5 | Trash retention | Items become purge-eligible after 30 days; user is notified and must confirm. Ignored items stay in trash |
| D6 | "Untouched" definition | File last-modified time older than threshold (last-access time is not reliably maintained on NTFS) |
| D7 | Threshold | User picks 3 months / 6 months / 1 year / 2 years; default 6 months |
| D8 | Scan scope | User profile folders + other fixed data drives; never system or app-data folders; Pictures unselected by default |
| D9 | OneDrive | Online-only files skipped; old locally-stored synced files offered "Free up space" instead of trash |
| D10 | App cache | Current user only, no admin; curated cache-folder list; running apps skipped; deleted permanently after confirmation (not trashed) |
| D11 | Purge reminder | Per-user daily Windows scheduled task running the app in hidden check mode; shows a notification; never deletes |
| D12 | Architecture | Scan in Dart (background isolate) into a local SQLite index |
| D13 | Duplicates | Identical content only: group by exact size → sample hash → full SHA-256. Online-only OneDrive files never read. Hard links to the same file are not duplicates |
| D14 | Duplicate keep rule | Preselect extras, user reviews. Keep priority: OneDrive copy → copy in Documents/Pictures/Desktop/Videos over Downloads or temp-like folders → oldest. At least one copy per group is always kept |
| D15 | Large files | Any age; threshold picker 100 MB / 250 MB / 500 MB / 1 GB / 2 GB, default 500 MB; files modified in the last 7 days shown but unselected |
| D16 | Similar photos | Near-identical copies only (resized, re-compressed, format-converted, light edits), strict fixed threshold. Burst/series shots not grouped |
| D17 | Similar-photo keep rule | Keep highest quality: most pixels → larger file → Pictures/Documents/Desktop over Downloads or temp-like → oldest; others preselected. Groups with an edited copy (crop or color change) flagged "Edited versions — choose yourself", nothing preselected. At least one photo per group always kept |

### Why not the Windows Recycle Bin (D4)
- Files larger than the bin's size limit are deleted permanently instead of recycled.
- Many USB drives have no Recycle Bin.
- Windows Storage Sense can empty the bin automatically after 30 days, bypassing the confirmation rule.

## 4. Access and permissions

Windows desktop apps need no special permission to read the user's own files. Three things can still block access:

| Situation | Handling |
|-----------|----------|
| Microsoft Defender **Controlled Folder Access** (ransomware protection) blocks unknown apps from changing files in Documents, Pictures, Desktop, etc. | Move fails with access denied → file skipped and reported, with instructions to allow the app in Windows Security |
| Files or folders the user doesn't own (other users' folders, system-protected files) | Skipped and counted |
| File open in another app (locked) | Skipped and reported as "in use" |

No admin rights are requested at any point.

## 5. Architecture

### 5.1 Screens (Flutter UI)

| Screen | Contents |
|--------|----------|
| Home | Disk usage per drive, space held by old files, total app cache, Scan button with progress |
| Old Files | Results grouped by category (Downloads, Documents, Videos, Audio, Pictures, Archives, Installers, Other), sorted by size. Each file shows its action: **Move to trash** or **Free up space (OneDrive)** |
| Large Files | Files at or above the size threshold, largest first, with age and location; same per-file actions as Old Files |
| Duplicates | Two tabs: **Exact duplicates** and **Similar photos**. "Analyze" button runs both passes with progress and cancel. Groups sorted by space recoverable; kept copy marked "Keep", extras preselected; user can change the kept copy |
| Similar photos tab | Side-by-side previews with resolution, file size, format, location and date; badge per group ("Resized copies", "Edited versions — choose yourself"); OneDrive copies labelled |
| App Cache | Apps ranked by cache size; per-app and "Clean selected"; running apps marked with "Close <app> to clean" |
| Trash | Trashed files with original location and days remaining; Restore, Delete now, Empty trash |
| Settings | Age threshold, large-file threshold, duplicate minimum size, similar-photo pass on/off, excluded folders, drives to scan, "Empty all trash", "Open trash folder" |

### 5.2 Core logic (pure Dart)

All file access goes through an abstraction (`package:file` plus a small platform interface for Windows-only attributes) so this layer runs against an in-memory filesystem in tests.

- **Scanner** — walks scan roots in a background isolate; reads names, sizes, timestamps and attributes from directory listings only (never opens file contents — only the duplicate finder reads contents); skips excluded folders, trash folders, and online-only OneDrive files; **never follows junctions, symbolic links or other reparse points**; writes to the index in batches; reports progress.
- **File index** — SQLite database (`drift`) of scanned files.
- **Categorizer** — category from extension and folder; marks Pictures as protected (unselected by default); marks files under OneDrive roots as `cloud_synced`.
- **Trash manager** — moves, restores, permanently deletes; maintains per-drive manifests; reconciles interrupted operations.
- **Duplicate finder** — runs after a scan, in a background isolate, cancellable and resumable. Pipeline:
  1. Candidates: indexed files ≥ the minimum size (default 1 MB, adjustable), not online-only, not in excluded or trash folders.
  2. Group by exact size; drop sizes with a single file.
  3. Collapse hard links (same NTFS file ID) — they share storage, so removing one frees nothing.
  4. Sample hash (first, middle and last 64 KB); drop unique samples.
  5. Full SHA-256 (via Windows CNG through FFI for speed); files with equal full hashes form a duplicate group.
  6. Hashes are stored with each file's size and modified time and reused on later runs if both are unchanged.
- **Similar-photo finder** — runs in the same "Analyze" pass after exact duplicates, in a background isolate, cancellable and resumable:
  1. Candidates: local (not online-only) images of type JPEG, PNG, HEIC/HEIF, WebP, BMP, TIFF; at least 100 KB and 256 px on the shortest side; not excluded. HEIC files are skipped and reported if the Windows HEIF codec isn't installed.
  2. Exact-duplicate sets are collapsed to their kept copy first, so nothing is reported twice.
  3. Fingerprint each image: decode at reduced size through the Windows Imaging Component, apply EXIF orientation, convert to grayscale, compute a 64-bit perceptual hash (DCT) and a 64-bit difference hash. Also record width, height, aspect ratio and a small color signature.
  4. Match: both hashes within a strict Hamming distance (initial value 4 of 64 bits each; final value calibrated on the labelled test set in §13). Candidate pairs found with bucketed hash lookup, not all-pairs comparison.
  5. Group: a photo joins a group only if it matches the group's kept photo directly (prevents A≈B≈C drift chains).
  6. Edited check: aspect ratio differs by more than 1%, or color signature differs beyond threshold → group flagged "Edited versions", no preselection.
  7. Fingerprints are stored with size and modified time and reused if unchanged.
- **Keep-rule engine** — chooses the kept copy per group (D14 for duplicates, D17 for similar photos) and enforces the at-least-one-copy invariant on every selection change.
- **Cache cleaner** — loads the curated cache catalog, measures each entry, detects running apps, deletes cache contents.
- **Purge checker** — finds trash items older than 30 days; used by the scheduled task and on app open.

### 5.3 Windows platform layer (Dart FFI via `package:win32`)

- **Known folders** — resolve Downloads, Documents, Desktop, Pictures, Videos, Music via `SHGetKnownFolderPath` (handles redirected and OneDrive-moved folders).
- **Drives** — list drives and types; scan `DRIVE_FIXED` drives by default; `DRIVE_REMOVABLE` off by default, user can enable; `DRIVE_REMOTE` never.
- **OneDrive** — find OneDrive roots from `HKCU\Software\Microsoft\OneDrive\Accounts\*\UserFolder`; detect online-only files from attributes (`RECALL_ON_DATA_ACCESS`, `RECALL_ON_OPEN`, `OFFLINE`); free up space by setting `UNPINNED` and clearing `PINNED` (equivalent to Explorer's "Free up space"), then verify the file became online-only.
- **Moves** — `MoveFileExW` **without** `MOVEFILE_COPY_ALLOWED`, so a move is always a same-volume rename and never a copy-then-delete. Long paths via the `\\?\` prefix.
- **Imaging** — decode and scale images and read dimensions/orientation via the Windows Imaging Component (WIC); thumbnails for previews via the Windows shell thumbnail API.
- **Processes** — list running process names to skip caches of open apps.
- **Notifications** — Windows toast notifications (requires an AppUserModelID and Start-menu shortcut, created by the installer).
- **Scheduled task** — create and remove the per-user daily task (Task Scheduler XML definition, no admin).

### 5.4 Hidden check mode

The same executable started with `--purge-check`:
- the Windows runner is modified so the window is never shown in this mode
- runs the purge checker, shows one notification if anything is ready, exits within a few seconds
- clicking the notification launches the app normally on the Trash screen

### 5.5 State management

Riverpod for UI state, with core logic exposed as providers.

## 6. Data model

Stored at `%LOCALAPPDATA%\StorageCleaner\index.db`.

### `files` table
| Column | Notes |
|--------|-------|
| `id` | Primary key |
| `path` | Current absolute path (unique) |
| `original_path` | Set when trashed |
| `drive_id` | Volume serial number (stable across drive-letter changes) |
| `size_bytes` | |
| `modified_at` | Last-modified time |
| `category` | Enum |
| `protected` | True for Pictures |
| `cloud_synced` | True under a OneDrive root |
| `state` | `indexed`, `moving`, `trashed`, `restoring`, `deleting`, `freeing`, `freed` |
| `trashed_at` | Set when trashed |
| `file_id` | NTFS file index (detects hard links) |
| `sample_hash` | Duplicate pipeline step 4; valid only while `size_bytes` and `modified_at` match |
| `full_hash` | SHA-256, same validity rule |
| `hashed_at` | When hashes were computed |
| `phash`, `dhash` | 64-bit perceptual and difference hashes (images only), same validity rule |
| `width`, `height` | Image dimensions after orientation |
| `color_sig` | Small color signature for edited-copy detection |

### Other tables
- **`folders`** — scanned folder path and last-modified time, to skip unchanged folders on rescan.
- **`scan_runs`** — start, end, status (`running`, `complete`, `interrupted`), counts; drives resume and "incomplete" labeling.
- **`exclusions`** — user-excluded folders.
- **`analysis_runs`** — type (`duplicates`, `similar_photos`), start, end, status, bytes read or images fingerprinted, groups found; drives resume after cancel or crash.
- **`cache_runs`** — when each cache entry was cleaned and how much was freed (for the "space freed" history).

Indexes: `(state, modified_at)` for Old Files; `(state, size_bytes)` for Large Files and duplicate candidates; `(size_bytes, full_hash)` for duplicate grouping; `(state, trashed_at)` for the purge check; unique on `path`.

Settings (age threshold, large-file threshold, duplicate minimum size, exclusions, enabled drives) are stored at `%APPDATA%\StorageCleaner\settings.json`.

## 7. Trash design (uninstall-safe)

### Location
- **System drive:** `%USERPROFILE%\StorageCleaner Trash` (e.g. `C:\Users\surya\StorageCleaner Trash`). This stays on the same volume, so moves are instant renames, and avoids needing write access to `C:\`.
- **Other drives:** `X:\StorageCleaner Trash`.
- A file is always trashed on its own drive. If the trash folder cannot be created on a drive, files on that drive cannot be trashed and the UI says why. **There is no copy-then-delete fallback.**

### Contents
- **Structure mirrors the original path**, keeping filenames: `C:\Users\surya\Downloads\report.pdf` → `...\StorageCleaner Trash\Downloads\report.pdf`. Name collisions get a suffix (`report (1).pdf`).
- **`README.txt`** — what the folder is, and how to recover files manually with File Explorer.
- **`manifest.json`** — for every item: trash path, original path, size, trash date. Updated after every trash, restore and delete; written atomically (write to temp file, then rename).
- The folder is marked **not content-indexed**, so trashed files don't appear in Windows Search results.

### Surviving uninstall and data loss
- The uninstaller removes the app, its scheduled task and its shortcuts, and **never deletes trash folders or settings**.
- **Uninstall warning:** unlike Android, Windows uninstallers can show a page. If trash holds files, the uninstaller says how many, how large, where they are kept, and offers to open the folder. It does not offer to delete them.
- On reinstall, or if `index.db` is lost, the app finds existing trash folders and rebuilds the trash list from their manifests.
- Settings in `%APPDATA%` are kept by the uninstaller and picked up on reinstall.

## 8. OneDrive "Free up space"

- Applies only to old files under a OneDrive root that are stored locally.
- Result: the local copy is removed, the file stays in OneDrive and on other devices, and it downloads again automatically when opened.
- Non-destructive, so it does not go through trash. It still has a confirmation dialog: "Free up 2.3 GB by keeping 87 files online-only? They stay in OneDrive and download again when opened."
- Files the user has marked "Always keep on this device" are shown with that label and unselected by default.
- If OneDrive isn't running or the user is signed out, the action is unavailable and the UI says so.
- After the action, the app re-reads attributes to confirm each file is online-only, and reports any that weren't freed.

## 9. App-cache design

### Catalog
A data file (`cache_catalog.json`) shipped with the app. Each entry has an app name, the process name(s) that indicate it is running, and the cache folder patterns, for example:
- Windows temp: `%TEMP%` (only items older than 24 hours and not locked)
- Chromium browsers (Chrome, Edge, Brave): `Cache`, `Code Cache`, `GPUCache` folders inside each profile
- Firefox: `cache2` inside each profile under `%LOCALAPPDATA%`
- Electron and other desktop apps (Teams, Slack, VS Code, Zoom, Spotify, Discord): their cache folders only

Exact paths are verified against current app versions during implementation and kept in the catalog, so they can be updated without changing code.

### Rules
- Only cache folders listed in the catalog are touched. **Never** cookies, login data, history, settings, extensions or downloads.
- Contents are deleted; the cache folder itself is kept.
- Paths are resolved and checked to be inside the expected parent folder before deleting; reparse points are never followed.
- If the app is running, that entry is skipped and shown as "Close <app> to clean".
- Locked files are skipped; the summary reports freed and skipped totals.
- Deleted **permanently** after a confirmation listing each app and its size (caches rebuild themselves, so trashing them would free nothing).

## 10. Data flows

1. **First launch** — short onboarding explaining review-first cleaning, trash, and that trash survives uninstall. App registers the daily scheduled task.
2. **Scan** — background walk of scan roots writes to the index in batches with live progress. Rescans skip folders whose modified time is unchanged and drop entries for files that no longer exist.
3. **Review** — query index for `state = indexed`, older than threshold, not excluded; group by category; show per-file action (trash or free up space). Pictures and "Always keep on this device" files unselected. Changing the threshold re-runs the query only.
4. **Move to trash** — select → confirmation dialog ("Move 142 files (3.8 GB) to trash?" with expandable list) → per file: re-check it exists and is unchanged → mark `moving` → rename → update manifest → mark `trashed`. Summary reports moved and skipped (in use, changed, access denied).
5. **Free up space** — select OneDrive files → confirmation → mark `freeing` → set attributes → verify → mark `freed`.
6. **Restore** — mark `restoring` → recreate original folder if missing → rename back → on name conflict, user chooses "keep both" (suffix) or a different folder → update manifest → mark `indexed`.
7. **Purge reminder** — daily task runs `--purge-check` → if items are past 30 days, one notification ("12 files (1.1 GB) ready to delete permanently") → click opens Trash with those preselected → strong confirmation → permanent delete. The same check runs whenever the app opens.
8. **Delete now / Empty trash** — strong confirmation ("This can't be undone", red non-default button) → permanent delete → update manifest.
9. **Large files** — query index for `state = indexed` and size ≥ threshold, largest first. Files modified in the last 7 days unselected. Actions as in flows 4 and 5. Changing the threshold re-runs the query only.
10. **Duplicates** — user taps "Find duplicates" → pipeline runs with progress (bytes read, groups found) → groups shown with keep-rule choices → user adjusts → confirmation → before each removal, re-check that the removed copy **and the kept copy** both still exist with unchanged size and modified time; if not, skip the whole group → move extras to trash (flow 4 steps). OneDrive extras follow the trash flow too, since the kept copy remains.
11. **Similar photos** — runs within "Analyze" → groups shown with previews and badges → for normal groups the highest-quality photo is kept and others preselected; edited groups have nothing preselected → user adjusts → confirmation → same re-checks as duplicates (removed and kept copies unchanged, else skip group) → extras to trash.
12. **App cache** — measure catalog entries → ranked list → user selects → confirmation with per-app sizes → delete contents → show space freed.

## 11. Confirmation rules

| Action | Confirmation |
|--------|-------------|
| Move to trash | Dialog with count, total size, expandable file list |
| Free up space (OneDrive) | Dialog with count, size, and explanation that files stay in OneDrive |
| Restore | None needed (non-destructive) |
| Delete now / Empty trash / Purge | Strong warning, explicitly irreversible, red non-default button |
| Clean app cache | Dialog listing each app and its size |
| Remove similar photos | Dialog with groups, photos removed, space freed, "these are similar, not identical — the highest-quality copy is kept", and a note if any removed copy is in OneDrive (removing it also removes it from OneDrive); extras go to trash |
| Remove duplicates | Dialog with groups, copies removed, space freed, and "one copy of each file is kept"; extras go to trash |
| Scheduled task | Never deletes; notification only |
| Uninstall | Uninstaller page shows trash contents are kept |

## 12. Error handling

| Situation | Behavior |
|-----------|----------|
| File in use (locked) | Skipped; reported as "in use" |
| Access denied / Controlled Folder Access | Skipped; reported with how to allow the app |
| Scan interrupted (app closed, shutdown, crash) | Batched writes keep partial results; next launch offers resume or restart; results labeled "incomplete" until complete |
| File deleted since scan | Skipped silently; index entry removed |
| File modified since scan | Skipped; reported ("3 skipped — changed since scan") |
| Crash mid-move | `moving` rows reconciled on next launch by checking which path exists; manifest and index corrected |
| Trash folder can't be created on a drive | Files on that drive can't be trashed; UI explains; no copy fallback |
| Path longer than 260 characters | Handled via `\\?\` paths; if the mirrored trash path would exceed limits, a shortened mirror path is used and recorded in the manifest |
| USB drive removed | Its trash items shown as "unavailable", excluded from purge, return when reconnected (matched by volume serial, even if the drive letter changes) |
| Index lost / reinstall | Trash rebuilt from manifests |
| Original folder gone on restore | Folder recreated |
| Name conflict on restore | User chooses keep both or another folder |
| OneDrive not running / signed out | Free up space unavailable; explained |
| File not freed by OneDrive | Reported; left as is |
| App running during cache clean | Entry skipped; "Close <app> to clean" |
| Scheduled task missing or disabled | Recreated on next app launch; purge check also runs on open |
| Junctions, symlinks, reparse points | Never followed (scanner and cache cleaner) |
| Unreadable folders | Skipped and counted in scan summary |
| File changes while being hashed | Dropped from its group; group re-evaluated |
| File can't be read during hashing (locked, access denied) | Excluded from duplicate results; counted in summary |
| Kept copy missing or changed at removal time | Whole group skipped; reported |
| Duplicate scan cancelled or interrupted | Completed hashes kept; next run resumes |
| Image can't be decoded (corrupt, unsupported, missing codec) | Excluded from similar photos; counted and reported by reason |
| User deselects the kept copy | Not allowed; UI requires choosing another copy to keep first |

## 13. Testing strategy

1. **Unit tests (Dart, in-memory filesystem)** — duplicate pipeline stages, keep-rule priority, hash reuse and invalidation, large-file query and recent-file default, categorizer, age filtering, exclusions, Pictures default, OneDrive classification, trash state transitions and crash reconciliation, manifest write and rebuild, restore conflicts, long-path mirroring, cache catalog path resolution and containment checks.
2. **Safety tests (release blockers)**
   - No duplicate selection or removal can ever remove every copy in a group, including when the kept copy disappears mid-operation.
   - Online-only OneDrive files are never opened or hashed (no download triggered).
   - Hard links are never reported as duplicates.
   - Similar-photo groups flagged as edited never have anything preselected.
   - No similar-photo selection can remove every photo in a group.
   - Permanent deletion reachable only through the confirmed delete paths (trash purge and cache clean); a test asserts no other code deletes.
   - Excluded folders, trash folders, system folders and `AppData` (outside catalog cache folders) are never scanned, moved or deleted.
   - Reparse points are never followed; a test plants a junction pointing at a protected folder and asserts nothing behind it is touched.
   - Files changed after the scan are never trashed.
   - Moves never fall back to copy-then-delete.
3. **Windows integration tests (CI on Windows runners + VMs)** — real moves and restores; long paths; locked files; multiple drives; drive-letter change; scheduled task create/remove; hidden check mode shows no window.
4. **Failure drills (scripted)** — kill the app mid-move; delete `index.db` → trash rebuilt; **uninstall and reinstall → every trashed file present and restorable**; Controlled Folder Access enabled; USB drive removed mid-session.
5. **OneDrive tests** — personal and work/school accounts; online-only skipped without triggering downloads; free up space verified; "Always keep on this device" respected; OneDrive not running.
6. **Similar-photo accuracy tests** — a labelled image set:
   - Positives: originals with resized, re-compressed, HEIC→JPEG, PNG→JPEG, EXIF-rotated and lightly filtered copies.
   - Negatives: burst shots of the same scene seconds apart, photos of similar subjects, screenshots of similar screens.
   - Targets: **zero negatives grouped**; ≥ 95% of resized/re-compressed copies found; every cropped or filtered copy flagged as edited. The match threshold is calibrated against this set.
7. **Cache tests** — each catalog entry against a current install of that app: only cache folders removed, app still signed in afterward, running app skipped.
8. **Performance** — 250,000-file fixture. Targets: first scan ≤ 60 s on a mid-range SSD laptop; rescans substantially faster; no UI freezes. Similar-photo pass: 20,000 photos fingerprinted in ≤ 5 minutes on a mid-range laptop, near-instant on repeat runs. Duplicate pass: bytes read reported; a repeat run on an unchanged disk re-reads nothing (hash reuse); cancel responds within 1 s.
9. **Environment matrix** — Windows 10 22H2 and Windows 11; standard (non-admin) user; corporate-style policies (Controlled Folder Access, OneDrive Known Folder Move).

## 14. Success criteria

- A user can scan, review and reclaim space in under 2 minutes on first use.
- Zero files permanently deleted without explicit confirmation (enforced by safety tests).
- Every trashed file is restorable after a crash, an index loss, or an uninstall and reinstall (enforced by failure drills).
- The duplicate and similar-photo finders never remove the last copy of any file or photo (enforced by safety tests).
- Similar-photo detection groups no burst shots or distinct photos in the labelled test set.
- Cache cleaning never signs the user out of any catalog app (enforced by cache tests).
- Installs and runs fully without admin rights.

## 15. Risks

| Risk | Mitigation |
|------|-----------|
| Antivirus or SmartScreen flags an unsigned app that deletes files | Code-sign all binaries; submit to Microsoft for reputation; document allow-listing for IT |
| Controlled Folder Access blocks moves in protected folders | Detect access-denied, explain how to allow the app; test with it enabled |
| Cache paths change when apps update | Catalog is data, not code; tests per app; unknown layouts are skipped rather than guessed |
| OneDrive "Free up space" behaves differently across versions or for work accounts | Verify attributes after the action; report failures; test personal and work accounts |
| Last-modified time flags files the user still opens | Review step, Pictures unselected by default, 30-day trash, restore |
| Trash folders left behind after uninstall use space | Uninstaller page explains and offers to open them; README in folder; "Empty all trash" in Settings |
| Duplicate scan slow on large disks | Only size-matched candidates are read; sample hash before full hash; hashes cached; cancellable and resumable; minimum size setting |
| Similar-photo detection groups photos the user considers different | Strict threshold calibrated on labelled negatives; group must match the kept photo directly; previews before removal; edited groups not preselected; trash |
| HEIC photos can't be read without the Windows HEIF codec | Skipped and reported with how to install the free codec |
| Two copies treated as duplicates when the user wants both (e.g. same file in two projects) | Review step, user can change the kept copy or deselect, trash makes removal reversible |
| Corporate IT blocks unknown installers | Per-user installer with no admin; packaging suitable for Intune deployment (decided in Delivery phase) |

## 16. Delivery requirements (detailed in Phase 6)

- Per-user installer, no admin rights.
- Creates the Start-menu shortcut with the app's AppUserModelID (needed for notifications).
- Uninstaller: removes app files, shortcut and scheduled task; keeps trash folders and settings; shows the trash warning page.
- All binaries code-signed.

## 17. Future work (not v1)

- macOS, then Android (design in superseded spec), then iOS photos-only.
- Admin-level system cleanup, or a shortcut to Windows Storage Sense.
- Per-category thresholds; burst/series-shot grouping with best-shot suggestion; adjustable similarity sensitivity; RAW formats.
- Optional Recycle Bin mode.
