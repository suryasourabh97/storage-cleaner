# ADR-003: Local SQLite index with hand-written SQL

**Status:** Accepted
**Date:** 2026-10-07
**Feature:** storage-cleaner
**Author:** 10x-Team (Architect + Staff Engineer)

## Context
Scans of 250k+ files must persist across launches, support instant threshold re-queries, rescan skipping, resume after interruption, and cached hashes/fingerprints. The spec named `drift`.

## Decision
- SQLite via `package:sqlite3` with a small repository class and hand-written SQL; schema versioned with `PRAGMA user_version` migrations.
- WAL mode; batched inserts in transactions (1,000 rows); indexes as in spec §6.
- The index is a **rebuildable cache**: trash state is recoverable from manifests; scan data from a rescan.
- This replaces `drift` from the spec (implementation detail, same behavior).

## Alternatives Considered
| Alternative | Pros | Cons | Why Not |
|-------------|------|------|---------|
| drift (ORM + codegen) | Typed queries, migrations | build_runner codegen step, more tooling for a ~6-table schema | Simplicity; fewer moving parts |
| In-memory only | Simplest | Rescan every launch; no resume or hash cache | Fails performance targets |
| JSON files | No native lib | No indexed queries over 250k rows | Too slow |

## Consequences
### Positive
- No codegen; SQL visible and reviewable.
### Negative
- Manual row mapping.
### Risks
- Native SQLite library availability in tests and the packaged app → bundle via `sqlite3_flutter_libs` (app) and use the system/CI SQLite for core tests.

## Dependencies
- ADR-001 (lives in `cleaner_core`).
