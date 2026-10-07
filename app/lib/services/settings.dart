import 'dart:convert';
import 'dart:io';

import 'package:cleaner_core/cleaner_core.dart';

/// User preferences, stored at `%APPDATA%\StorageCleaner\settings.json`.
/// `%APPDATA%` is kept by the uninstaller, so preferences survive a
/// reinstall. Exclusions live in the index database.
final class AppSettings {
  AppSettings({
    this.age = AgeThreshold.defaultValue,
    this.size = SizeThreshold.defaultValue,
    this.scanRemovableDrives = false,
    this.duplicateMin = DuplicateMinSize.defaultValue,
    this.similarPhotos = true,
  });

  AgeThreshold age;
  SizeThreshold size;
  bool scanRemovableDrives;
  DuplicateMinSize duplicateMin;

  /// Also look for near-identical photo copies when checking duplicates.
  bool similarPhotos;

  static AppSettings load(String path) {
    try {
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      return AppSettings(
        age: AgeThreshold.values.firstWhere(
          (a) => a.name == json['age'],
          orElse: () => AgeThreshold.defaultValue,
        ),
        size: SizeThreshold.values.firstWhere(
          (s) => s.name == json['size'],
          orElse: () => SizeThreshold.defaultValue,
        ),
        scanRemovableDrives: json['scanRemovableDrives'] == true,
        duplicateMin: DuplicateMinSize.values.firstWhere(
          (d) => d.name == json['duplicateMin'],
          orElse: () => DuplicateMinSize.defaultValue,
        ),
        similarPhotos: json['similarPhotos'] != false,
      );
    } on Object {
      return AppSettings();
    }
  }

  void save(String path) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'age': age.name,
        'size': size.name,
        'scanRemovableDrives': scanRemovableDrives,
        'duplicateMin': duplicateMin.name,
        'similarPhotos': similarPhotos,
      }));
  }
}
