/// Platform-neutral cleaning engine for Storage Cleaner.
///
/// Pure Dart: no Flutter and no Win32 imports (ADR-001). All file changes go
/// through [FileMutator] (ADR-006).
library;

export 'src/duplicates/duplicate_finder.dart';
export 'src/duplicates/hasher.dart';
export 'src/duplicates/keep_rules.dart';
export 'src/index/index_db.dart';
export 'src/model/models.dart';
export 'src/model/path_key.dart';
export 'src/platform/platform_fs.dart';
export 'src/purge/purge_checker.dart';
export 'src/query/queries.dart';
export 'src/safety/file_mutator.dart';
export 'src/safety/path_guard.dart';
export 'src/scan/categorizer.dart';
export 'src/scan/scanner.dart';
export 'src/trash/manifest.dart';
export 'src/trash/reconciler.dart';
export 'src/trash/trash_manager.dart';
