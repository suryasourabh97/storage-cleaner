# Project Status — storage-cleaner

**Feature slug:** `storage-cleaner`
**Current phase:** Phase 0 — Brainstorming (in progress)
**Started:** 2026-10-06

## Idea
Mobile app that finds files untouched for a long time and removes them to free space, plus clears installed apps' cache.

## Answered
- Platform: Android + iOS via cross-platform framework (iOS will be a reduced feature set)
- Framework: Flutter (Dart) with Kotlin/Swift platform channels for native storage APIs
- Deletion: user reviews flagged files by category, selected files move to in-app trash, auto-purged after 30 days; 'empty trash now' option
- App cache (Android only): list apps by cache size via StorageStatsManager (Usage access permission); 'Clean all' via system clear-all-caches prompt on Android 11+; per-app deep link to app storage settings (all versions, only option on 8-10). No Accessibility automation. iOS: no cache feature.
- Staleness: file last-modified older than threshold; user picker 3m/6m/1y/2y, default 6 months; changing threshold re-filters cached scan results (no rescan). Per-category thresholds deferred.

## Open questions
- Scan scope and protected/excluded locations

## Blockers
None yet.
