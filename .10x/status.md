# Project Status — storage-cleaner

**Feature slug:** `storage-cleaner`
**Current phase:** Phase 0 — Brainstorming (reopened 2026-10-07 for scope change)
**Phase 0:** Complete — spec approved 2026-10-06
**Started:** 2026-10-06

## Idea
Android app (v1) that finds files untouched for a long time and removes them to free space, plus clears installed apps' cache.

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
Open questions:
- Laptop support replaces Android, or is added alongside it?
- Which desktop OSes (Windows / macOS / Linux)?
- Laptop-specific design: OS Recycle Bin/Trash vs own trash, app caches, last-access time availability

## Next
- Resolve scope-change questions, revise spec, re-approve, then resume Phase 1

## Blockers
None yet.
