# CTO — storage-cleaner

**Date:** 2026-10-07
**Spec:** `.10x/specs/2026-10-07-storage-cleaner-windows-design.md` (approved 2026-10-07)

## Business context
- Problem: laptops fill up with forgotten old files, large files, duplicate and near-duplicate photos, and app caches. Users lack a safe, reviewable way to reclaim space.
- **Purpose of the app: not confirmed by the user** (public product vs internal/showcase vs client deliverable). Assumption used for Phase 1: build to product quality (signed, installable, safety-tested). This assumption does not change v1 engineering scope; it affects distribution and monetization only, which are decided in Phase 6. **Revisit before Delivery.**

## Build vs buy
| Option | Verdict |
|--------|---------|
| Windows Storage Sense / Disk Cleanup (built in, free) | Covers temp files, Recycle Bin, Downloads by age, OneDrive dehydration of unused files. No duplicate/similar-photo finder, no per-file review of arbitrary old files, no recoverable trash with uninstall-safe guarantees |
| CCleaner, BleachBit | Strong on cache/junk cleaning; weaker on duplicate/similar photos; deletions generally permanent |
| Dedicated duplicate finders (dupeGuru, etc.) | Duplicates only |
| **Build** | **Chosen.** Differentiator: one app combining old/large/duplicate/similar-photo/cache cleanup with review-first, recoverable, never-lose-a-file guarantees, under a standard user account |

## Technology direction
- Flutter desktop (Windows) + Dart FFI via `package:win32`. Rationale: user's choice; core logic stays pure Dart and portable to macOS/Android later (Android design preserved in superseded spec).
- No admin rights anywhere; no cloud backend; no telemetry in v1 (nothing leaves the device).

## Risk assessment
| Risk | Reversibility | Note |
|------|---------------|------|
| v1 scope is large (5 cleaning features) | Two-way | Mitigated by milestone plan: a usable, safe build exists after Milestone 1; later features layer on |
| Antivirus/SmartScreen distrust of a file-deleting app | Two-way | Code signing required before any distribution |
| Wrongly removed user files | Low blast radius by design | Review + trash + manifests + release-blocking safety tests |
| Build environment | — | Cloud workspace cannot fetch Flutter/Dart SDK; builds need user's Windows PC or Windows CI |

## Success criteria / review point
- Spec §14 criteria. Review this decision after Milestone 1 build is in the user's hands.
