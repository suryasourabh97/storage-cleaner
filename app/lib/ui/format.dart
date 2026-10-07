import 'package:cleaner_core/cleaner_core.dart';

/// 1536 -> "1.5 KB". Uses 1024-based units, as File Explorer does.
String formatBytes(int bytes) {
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
  if (bytes < 1024) return bytes == 1 ? '1 byte' : '$bytes bytes';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// "3 files" / "1 file".
String plural(int n, String one, [String? many]) =>
    '$n ${n == 1 ? one : (many ?? '${one}s')}';

String formatDate(DateTime t) {
  final l = t.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${l.day} ${months[l.month - 1]} ${l.year}';
}

String ageLabel(AgeThreshold a) => switch (a) {
      AgeThreshold.months3 => '3 months',
      AgeThreshold.months6 => '6 months',
      AgeThreshold.year1 => '1 year',
      AgeThreshold.years2 => '2 years',
    };

String sizeLabel(SizeThreshold s) =>
    s.megabytes >= 1024 ? '${s.megabytes ~/ 1024} GB' : '${s.megabytes} MB';

String categoryLabel(Category c) => switch (c) {
      Category.downloads => 'Downloads',
      Category.documents => 'Documents',
      Category.videos => 'Videos',
      Category.audio => 'Audio',
      Category.pictures => 'Pictures',
      Category.archives => 'Archives',
      Category.installers => 'Installers',
      Category.other => 'Other',
    };

String skipReasonLabel(SkipReason r) => switch (r) {
      SkipReason.notFound => 'no longer exists',
      SkipReason.changedSinceScan => 'changed since the scan',
      SkipReason.inUse => 'open in another app',
      SkipReason.accessDenied =>
        'access denied (Windows Security may be blocking the app)',
      SkipReason.crossVolume => 'on a different drive',
      SkipReason.guardRejected => 'in a protected location',
      SkipReason.alreadyExists => 'name already taken',
      SkipReason.trashUnavailable => 'trash folder unavailable on that drive',
      SkipReason.notConfirmed => 'not confirmed',
      SkipReason.volumeUnavailable => 'drive not connected',
      SkipReason.wrongState => 'not in the expected state',
      SkipReason.keptCopyChanged =>
        'kept copy changed or missing, so its group was left alone',
      SkipReason.ioError => 'Windows reported an error',
    };

/// "139 moved. 3 skipped: 2 open in another app, 1 changed since the scan."
String summarizeBatch(BatchResult r, String verb) {
  final done = '${plural(r.doneCount, 'file')} $verb.';
  if (r.skippedCount == 0) return done;
  final counts = <SkipReason, int>{};
  for (final s in r.skipped) {
    counts[s.reason] = (counts[s.reason] ?? 0) + 1;
  }
  final parts = [
    for (final e in counts.entries) '${e.value} ${skipReasonLabel(e.key)}',
  ];
  return '$done ${r.skippedCount} skipped: ${parts.join(', ')}.';
}

String minSizeLabel(DuplicateMinSize m) => switch (m) {
      DuplicateMinSize.kb100 => '100 KB',
      DuplicateMinSize.mb1 => '1 MB',
      DuplicateMinSize.mb10 => '10 MB',
      DuplicateMinSize.mb100 => '100 MB',
    };
