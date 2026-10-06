# Project Status — storage-cleaner

**Feature slug:** `storage-cleaner`
**Current phase:** Phase 0 — Brainstorming (in progress)
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

## Open questions
- 30-day auto-purge: how to confirm when no user is present

## Next
- Present design section by section for approval (components, data flow, error handling, testing)

## Blockers
None yet.
