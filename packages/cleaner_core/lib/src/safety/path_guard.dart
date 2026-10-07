import '../model/path_key.dart';
import '../platform/platform_fs.dart';

/// Locations the engine may and may not change (ADR-006).
final class GuardConfig {
  GuardConfig({
    required List<String> allowedRoots,
    List<String> protectedRoots = const [],
    List<String> protectedExceptions = const [],
  })  : allowedRoots = List.unmodifiable(allowedRoots.map(normalizePath)),
        protectedRoots = List.unmodifiable(protectedRoots.map(normalizePath)),
        protectedExceptions =
            List.unmodifiable(protectedExceptions.map(normalizePath));

  /// Scan roots and trash roots. Paths must be strictly inside one of these.
  final List<String> allowedRoots;

  /// Never touched: Windows, Program Files, ProgramData, AppData, ...
  final List<String> protectedRoots;

  /// Folders inside a protected root that are still allowed (resolved app
  /// cache folders from the cache catalog).
  final List<String> protectedExceptions;
}

sealed class GuardResult {
  const GuardResult();
}

final class GuardOk extends GuardResult {
  const GuardOk();
}

final class GuardRejected extends GuardResult {
  const GuardRejected(this.why);
  final String why;
}

/// Decides whether a path may be changed. Every `FileMutator` call goes
/// through [check].
final class PathGuard {
  PathGuard(this._fs, this.config);

  final PlatformFs _fs;
  final GuardConfig config;

  GuardResult check(String path) {
    final normalized = normalizePath(path);
    if (!winPath.isAbsolute(normalized)) {
      return const GuardRejected('not an absolute path');
    }

    final inAllowed = config.allowedRoots.any((r) => isWithin(r, normalized));
    if (!inAllowed) return const GuardRejected('outside allowed roots');

    for (final protected in config.protectedRoots) {
      if (isWithinOrEqual(protected, normalized)) {
        final excepted = config.protectedExceptions
            .any((e) => isWithin(e, normalized));
        if (!excepted) return GuardRejected('protected location: $protected');
      }
    }

    // Reject if the path itself or any ancestor is a link (junction,
    // symlink, mount point): following one could redirect the operation
    // somewhere else entirely.
    var current = normalized;
    while (true) {
      final entry = _fs.stat(current);
      if (entry != null && entry.attrs.isLink) {
        return GuardRejected('link in path: $current');
      }
      final parent = winPath.dirname(current);
      if (samePath(parent, current)) break;
      current = parent;
    }
    return const GuardOk();
  }

  bool allows(String path) => check(path) is GuardOk;
}

/// Default protected locations for a Windows user profile.
List<String> defaultProtectedRoots({
  required String windowsDir,
  required String userProfile,
  required List<String> driveRoots,
}) =>
    [
      windowsDir,
      winPath.join(userProfile, 'AppData'),
      for (final d in driveRoots) ...[
        winPath.join(d, 'Program Files'),
        winPath.join(d, 'Program Files (x86)'),
        winPath.join(d, 'ProgramData'),
        winPath.join(d, r'$Recycle.Bin'),
        winPath.join(d, 'System Volume Information'),
        winPath.join(d, 'Recovery'),
      ],
    ];
