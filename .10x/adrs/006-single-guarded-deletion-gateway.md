# ADR-006: All destructive file operations go through one guarded gateway

**Status:** Accepted
**Date:** 2026-10-07
**Feature:** storage-cleaner
**Author:** 10x-Team (Architect + Staff Engineer)

## Context
Safety requirements: never delete without confirmation, never touch system/AppData (except catalog cache folders), never follow reparse points, never remove the last duplicate copy. These must be enforced by code and tests, not convention.

## Decision
- `cleaner_core` exposes exactly one class that can mutate user files: `FileMutator` (move, rename back, delete, dehydrate). No other code calls delete/rename APIs; a test scans the source tree to enforce this.
- Every call passes through `PathGuard`, which rejects: paths outside allowed roots; protected locations (`Windows`, `Program Files*`, `ProgramData`, `AppData` except resolved catalog cache dirs); any path whose components include a reparse point; trash-root misuse.
- Permanent deletes require a `DeletionConfirmation` token that only the confirmation flows can mint (issued for a specific item set; expires after use).
- Duplicate/similar removals are validated by `KeepRuleEngine` immediately before calling the mutator.

## Alternatives Considered
| Alternative | Pros | Cons | Why Not |
|-------------|------|------|---------|
| Checks in each feature | Less indirection | Easy to forget one path | Safety must be centralized |
| OS ACL sandboxing | Strong | Not available to a normal desktop app per-path | Not feasible |

## Consequences
### Positive
- One place to audit and test safety.
### Negative
- Slight ceremony for every operation.
### Risks
- Guard false positives blocking legitimate files → reported, never silently skipped.

## Dependencies
- Used by ADR-002 (trash), ADR-004 (removals), cache cleaner, OneDrive free-up-space.
