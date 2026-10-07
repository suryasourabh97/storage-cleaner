# ADR-005: Daily reminder via per-user scheduled task and hidden check mode

**Status:** Accepted
**Date:** 2026-10-07
**Feature:** storage-cleaner
**Author:** 10x-Team (Architect + Staff Engineer)

## Context
Trash items older than 30 days need a reminder; nothing may be deleted without confirmation; no admin; no always-running process.

## Decision
- Register a per-user Task Scheduler task `\StorageCleaner\PurgeCheck` (daily, `StartWhenAvailable`) via `schtasks.exe /Create /XML` from the app; recreated on launch if missing; removed by the uninstaller.
- Action runs the same executable with `--purge-check`. The Windows runner skips showing the window in this mode; Dart runs `PurgeChecker` (read-only), shows one toast if items are due, and exits.
- The purge check also runs on every normal launch.

## Alternatives Considered
| Alternative | Pros | Cons | Why Not |
|-------------|------|------|---------|
| Check only on app open | Nothing in background | No reminder if app not opened | User chose daily reminder |
| Tray app at startup | Always available | Constant memory use, disliked by IT | User chose scheduled task |
| Task Scheduler COM via FFI | No CLI | Verbose COM interop | CLI with XML is simpler and sufficient |

## Consequences
### Positive
- Zero resident footprint; can't delete anything.
### Negative
- Depends on runner modification and toast registration (AppUserModelID shortcut from installer).
### Risks
- Corporate policy disabling Task Scheduler for users → falls back to on-launch check.

## Dependencies
- Delivery (Phase 6): installer must create the shortcut and remove the task.
