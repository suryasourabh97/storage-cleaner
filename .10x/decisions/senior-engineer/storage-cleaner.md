# Senior Engineer — storage-cleaner (M1 implementation approach)

## Approach per task
- **1.3 MemoryPlatformFs:** map of normalized `PathKey` → node {isDir, bytes, mtime, attrs, fileId, volume}; volumes keyed by root (`C:\`, `D:\`); `move` fails with `crossVolume` if volumes differ, `locked` if path in lock set, `accessDenied` if marked. Directory mtime updates on child add/remove (needed for rescan skipping).
- **1.4 PathGuard:** allowed roots = scan roots ∪ trash roots ∪ catalog cache dirs. Protected = `%WINDIR%`, `Program Files`, `Program Files (x86)`, `ProgramData`, `%USERPROFILE%\AppData` (allowed only under resolved catalog cache dirs). Walk each ancestor from the root; reject if any is a reparse point. Case-insensitive prefix match on path segments (not raw string prefix: `C:\Users\a` must not match `C:\Users\ab`).
- **1.5 FileMutator:** methods return `OpOutcome`; `delete` requires a `DeletionConfirmation` whose item set contains the path; token single-use. Enforcement test: grep `packages/cleaner_core/lib` for `.move(`, `.delete(`, `.dehydrate(` outside `file_mutator.dart` and the interface file.
- **1.6 IndexDb:** tables per spec §6 (+ hashes/fingerprint columns present but unused until M3/M4 to avoid migrations). WAL. Prepared statements. `upsertFiles(List)` in a transaction.
- **1.8 Scanner:** iterative DFS with explicit stack (no recursion limits). Skip: reparse points, hidden+system dirs, names starting with `.`, excluded, trash roots, protected. Online-only files recorded with `online_only=1` (excluded from queries). Folder skipping: if folder mtime equals stored mtime and the scan run is not `full`, reuse children rows (mark seen). After walk: delete rows not seen in this run under scanned roots (only `indexed` state). Batch 1,000; emit progress per batch; check cancel per entry.
- **1.9 Queries:** SQL with `state='indexed' AND online_only=0 AND modified_at < ?`; exclusions via path-prefix `LIKE` with escaped wildcards and trailing separator; preselect = not protected (old) / not modified within 7 days (large).
- **1.11 TrashManager.move:** per item: stat → compare size+mtime with index → else skip(changed); compute trash path on same volume; set `moving` + intended trash path (index) → mutator.move → manifest add → `trashed`. Collision: ` (n)` before extension.
- **1.11 restore:** `restoring` → ensure parent dirs → if target exists: return `conflict` for UI choice (keepBoth → suffix, or user-chosen dir) → move → manifest remove → `indexed`.
- **1.12 Reconciler:** for `moving`: if file at trash path → finish (`trashed`, ensure manifest); else if at original → revert to `indexed`; else mark `missing` and report. Same logic mirrored for `restoring`. Rebuild: if index empty/missing, read all manifests on available volumes → insert `trashed` rows.
- **1.13 PurgeChecker:** `trashed_at < now - 30d` and volume available → summary {count, bytes, ids}; pure read.

## Tricky parts
- Case-insensitive path identity and segment-aware prefix checks.
- Atomic manifest writes on Windows: write `manifest.json.tmp` then `MoveFileEx(REPLACE_EXISTING)`; in fake, rename semantics.
- Never trusting index data at action time: always re-stat.
