# Engineering Manager — storage-cleaner

**Date:** 2026-10-07

## Milestones
| M | Outcome | Usable alone? |
|---|---------|---------------|
| M1 | Core engine: scan, index, old/large queries, safety gateway, trash/restore/purge, manifests, reconciliation — with unit + safety tests | Engine only (headless) |
| M2 | Windows adapter + Flutter UI for M1 features (Home, Old Files, Large Files, Trash, Settings) | **Yes — first usable app** |
| M3 | Exact duplicates + keep rules + Duplicates screen | Yes |
| M4 | Similar photos (pHash/dHash, WIC decoder, labelled test set, previews) | Yes |
| M5 | App cache catalog + cleaner; OneDrive free-up-space | Yes |
| M6 | Scheduled task + hidden check mode + toasts; installer, signing (Phase 6) | Release candidate |

## M1 task breakdown (≤ half day each, in order)
| # | Task | Depends on |
|---|------|-----------|
| 1.1 | Monorepo skeleton: `packages/cleaner_core` pubspec, analysis options, CI workflow | — |
| 1.2 | Models: FileEntry, Category, ItemState, PathKey, OpOutcome, Progress, CancelToken | 1.1 |
| 1.3 | Platform interfaces + `MemoryPlatformFs` fake (volumes, attributes, reparse points, locks, file IDs) | 1.2 |
| 1.4 | PathGuard (protected locations, reparse-point components, allowed roots) + tests | 1.3 |
| 1.5 | FileMutator + DeletionConfirmation + source-scan enforcement test | 1.4 |
| 1.6 | IndexDb: schema v1, migrations, batched upserts, queries | 1.2 |
| 1.7 | Categorizer + tests | 1.2 |
| 1.8 | Scanner: walk, skip rules, folder-mtime skipping, batching, progress, cancel, resume | 1.3, 1.6, 1.7 |
| 1.9 | Old/Large queries (threshold, exclusions, protected/recent defaults) | 1.6 |
| 1.10 | Manifest (atomic write, read, rebuild) | 1.3 |
| 1.11 | TrashManager: move (pre-checks, two-phase), restore (conflicts, recreate dir), delete-with-confirmation | 1.5, 1.6, 1.10 |
| 1.12 | Reconciler (moving/restoring rows; manifest-first rebuild) + failure-drill tests | 1.11 |
| 1.13 | PurgeChecker | 1.11 |
| 1.14 | Safety test suite consolidation + `dart analyze` clean | all |

## Estimates
- M1 ≈ 6–7 working days; M2 ≈ 5; M3 ≈ 3; M4 ≈ 5; M5 ≈ 4; M6 ≈ 4 (+ Play-free signing setup). Total ≈ 27–28 days for one engineer.

## Risks / unknowns
| Risk | Plan |
|------|------|
| No Flutter/Dart toolchain in cloud workspace | Verify via user's Windows PC (linked) or GitHub Actions `windows-latest` + `ubuntu-latest` for core |
| sqlite3 native lib for core tests | Ubuntu CI has libsqlite3; Windows CI uses `sqlite3` package's bundled/provided DLL — confirm in 1.1 |
| win32 coverage for WIC/CNG | Spike at start of M2/M4 |

## M2 task breakdown (2026-10-07)
| # | Task | Depends on |
|---|------|-----------|
| 2.1 | `app/` Flutter project + windows-latest workflow (generate runner with `flutter create`, analyze, test, build, upload exe artifact) | M1 |
| 2.2 | `WindowsPlatformFs` via FFI + known folders, drives, disk space; real-filesystem tests on the Windows runner | 2.1 |
| 2.3 | App services: engine wiring, scan in a background isolate (progress, cross-isolate cancel), settings file, launch reconciliation | 2.2 |
| 2.4 | Screens: Home, Old Files, Large Files, Trash, Settings + confirmation dialogs | 2.3 |
| 2.5 | CI green, state files, deliver build | all |

Verification loop: GitHub Actions (findings surfaced as annotations).
