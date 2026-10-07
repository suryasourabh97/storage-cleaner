# Product Manager — storage-cleaner

**Date:** 2026-10-07

## Problem statement
Windows laptop users run low on disk space but can't safely tell which files are forgotten, oversized, duplicated or redundant, and fear deleting something they need.

## Target user
A laptop user with a standard (non-admin) account, often a company laptop with OneDrive Known Folder Move and Defender protections.

## User stories (priority)
| P | Story |
|---|-------|
| P0 | As a user, I want to see how much space old files take and review them by category, so I can reclaim space without hunting manually |
| P0 | As a user, I want removed files to go to a recoverable trash, so a mistake is never permanent |
| P0 | As a user, I want every permanent deletion to ask me first, including the 30-day purge |
| P0 | As a user, I want trashed files to survive if the app is uninstalled |
| P0 | As a user, I want to find large files of any age |
| P1 | As a user, I want old/large OneDrive files freed locally without deleting them from the cloud |
| P1 | As a user, I want exact duplicates found, with the best copy kept automatically |
| P1 | As a user, I want resized/re-saved copies of photos found, keeping the best-quality one, and never auto-choosing between edited versions |
| P1 | As a user, I want app caches cleaned without being signed out of anything |
| P1 | As a user, I want a reminder when trash items are ready to delete |

All P0 + P1 are in v1 (user decision). Delivery is staged by milestone (see engineering-manager plan) so P0 ships first internally.

## Out of scope (v1)
Spec §2: other OSes, admin-level cleanup, network drives, automatic cleanup, burst-shot grouping, adjustable similarity, RAW/video similarity, Recycle Bin mode.

## Success metrics
- First-use scan → review → reclaim in < 2 minutes.
- Zero unconfirmed permanent deletions; zero last-copy removals (safety tests).
- 100% of trashed files restorable after crash / index loss / reinstall (failure drills).
- No sign-outs from cache cleaning (cache tests).
- Similar photos: zero false groups on labelled negatives; ≥ 95% recall on resized copies.

## Risks
- Scope size → staged milestones.
- Users misunderstanding "Free up space" vs delete → explicit dialog copy.
