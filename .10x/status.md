# Project Status — storage-cleaner

**Feature slug:** `storage-cleaner`
**Current phase:** Phase 0 — Brainstorming: Windows spec updated with similar-photo detection, awaiting user review
**Phase 0:** Complete — spec approved 2026-10-06
**Started:** 2026-10-06

## Idea
Windows laptop app (v1; was Android) that finds files untouched for a long time and removes them to free space, plus clears installed apps' cache.

## Answered
- Platform: Android + iOS via cross-platform framework (iOS will be a reduced feature set)
- Framework: Flutter (Dart) with Kotlin/Swift platform channels for native storage APIs
- Deletion: user reviews flagged files by category, selected files move to in-app trash, auto-purged after 30 days; 'empty trash now' option
- App cache (Android only): list apps by cache size via StorageStatsManager (Usage access permission); 'Clean all' via system clear-all-caches prompt on Android 11+; per-app deep link to app storage settings (all versions, only option on 8-10). No Accessibility automation. iOS: no cache feature.
- Staleness: file last-modified older than threshold; user picker 3m/6m/1y/2y, default 6 months; changing threshold re-filters cached scan results (no rescan). Per-category thresholds deferred.
- Scan scope (Android): all readable shared storage; camera media (DCIM) shown but unselected by default; skip hidden dirs/config files; user-managed exclusion list.
- Release plan: v1 is Android-only. Flutter codebase stays iOS-ready; iOS (likely photos-only via PhotoKit) is a later release.
- Architecture approach: A — Dart-side scan in background isolate + local SQLite index; Kotlin only for permissions, app-cache stats/intents; MediaStore used for quick first estimate; trash = same-volume rename into hidden folder.
- Confirmation required before every deletion: confirm dialog on Move to trash (count + size + list); stronger confirm on Delete now / Empty trash (permanent, typed or explicit). Cache clear confirmed by Android system prompt.
- 30-day purge: daily background check notifies when items pass 30 days; nothing is deleted until user opens and confirms. Ignored items stay in trash.
- Design part 1 (components) approved with confirmation additions.
- Design part 2 (data flow) approved.
- Design part 3 (error handling) approved, plus uninstall-survival requirement:
  - Trash folder is VISIBLE: 'StorageCleaner Trash/' per volume (with .nomedia), mirrors original folder structure, keeps original filenames (suffix on collision)
  - README.txt + manifest.json in each trash folder for manual recovery without the app
  - Reinstalled app adopts existing trash folders from manifest
  - Settings (threshold, exclusions) backed up via Android Auto Backup; scan index excluded (rebuildable)
  - android:hasFragileUserData=true so uninstall dialog offers to keep app data
  - Android gives no pre-uninstall hook; no warning at uninstall time is possible

- Design part 4 (testing strategy) presented; user asked for spec.

## Scope change (2026-10-07)
User asked to update the application to clean unused files on laptops. Phase 1 paused (purpose question unanswered) and brainstorming reopened.
Decided:
- Laptop REPLACES Android: v1 is a laptop-only (desktop) cleaner. Android design kept in spec as possible later release.
- OS: Windows only for v1.
- Trash: app's own 'StorageCleaner Trash' folder per drive (README + manifest, 30-day notify-and-confirm). Not the Windows Recycle Bin (size-limit permanent deletes, no bin on many USB/network drives, Storage Sense auto-empty bypasses confirmation).
- Cache: current user account only, no admin. %TEMP% + curated list of known app cache folders (Chrome, Edge, Firefox, Teams, Slack, VS Code, Zoom, Spotify...). Cache folders only, never cookies/logins/history/settings. Skip running apps with 'close X' hint. Caches deleted permanently after confirmation dialog showing size per app (not trashed).
- Scan scope: user profile folders + other fixed data drives. Never Windows, Program Files, ProgramData, AppData. Pictures shown but unselected by default. OneDrive: skip online-only placeholders; old locally-stored synced files get 'Free up space' (dehydrate to online-only, file stays in cloud) instead of trash. Non-synced files use trash flow.
- Purge reminder: per-user daily Windows Task Scheduler task (no admin) runs the app in hidden check mode; shows toast if trash items >30 days; click opens Trash. Task removed on uninstall. Never deletes.

## Scope addition (2026-10-07)
User added to v1: duplicate file detection, large-file finder independent of age.
Decided:
- Duplicates = identical content only. Pipeline: group by exact size -> partial sample hash -> full hash. Online-only OneDrive files never read. Similar-photo detection deferred.
- Duplicate keep rule: preselect extras, user reviews. Keep priority: OneDrive copy > Documents/Pictures/Desktop/Videos over Downloads/temp-like > oldest. App always keeps >=1 copy per group (cannot select all). Removed duplicates go to 30-day trash.
- Large files: any age; user picker 100MB/250MB/500MB/1GB/2GB, default 500MB; instant re-query; OneDrive large files get Free up space; files modified in last 7 days shown but unselected.

## Scope addition 2 (2026-10-07)
User added similar-photo detection to v1.
Decided:
- Similar = near-identical copies only (resized, re-compressed, format-converted, light edits). Strict fixed threshold. Burst/series shots and adjustable sensitivity deferred.
- Similar keep rule: highest quality kept (pixels > file size > location > oldest), rest preselected; if a copy looks edited (crop/aspect change or color change) the group is flagged 'Edited versions' with nothing preselected. >=1 kept, extras to trash, side-by-side previews.

## Next
- User reviews `.10x/specs/2026-10-07-storage-cleaner-windows-design.md`, then resume Phase 1 `.10x/specs/2026-10-07-storage-cleaner-windows-design.md`
- On approval: resume Phase 1 (Strategy). Unanswered Phase 1 question: app purpose (public product / internal-showcase / client deliverable)

## Blockers
None yet.
