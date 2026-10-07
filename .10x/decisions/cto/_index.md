# CTO — decisions index

## Active features
| Slug | Description | Status |
|------|-------------|--------|
| storage-cleaner | Windows laptop cleaner: old/large/duplicate/similar-photo/cache, review-first with recoverable trash | Phase 1 complete |

## Cross-cutting principles
- Never lose user data: every destructive action is confirmed, and file removal is recoverable by default.
- No admin rights, no backend, nothing leaves the device in v1.
- Keep core logic platform-neutral (pure Dart) so other platforms can follow.
