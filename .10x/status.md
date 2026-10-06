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

## Open questions
- Android app-cache clearing approach: settings deep-link vs Accessibility automation

## Blockers
None yet.
