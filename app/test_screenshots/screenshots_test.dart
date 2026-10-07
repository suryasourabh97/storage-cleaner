@TestOn('windows')
library;

// Renders every screen against a demo profile and writes PNGs with
// `flutter test test_screenshots --update-goldens`. CI publishes them to the
// `ci-screenshots` branch so the design can be reviewed without a Windows PC.

import 'dart:io';
import 'dart:math' as math;

import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:storage_cleaner/main.dart';
import 'package:storage_cleaner/platform/flutter_image_decoder.dart';
import 'package:storage_cleaner/services/app_controller.dart';
import 'package:storage_cleaner/ui/theme.dart';

const demoRoot = r'C:\ScreenshotDemo';
const profile = '$demoRoot\\Asha';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  var any = false;
  for (final f in files) {
    final file = File(f);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      any = true;
    }
  }
  if (any) await loader.load();
}

Future<void> _loadFonts() async {
  const dir = r'C:\Windows\Fonts';
  final segoe = [
    '$dir\\segoeui.ttf',
    '$dir\\segoeuib.ttf',
    '$dir\\segoeuisl.ttf',
    '$dir\\seguisb.ttf',
    '$dir\\segoeuil.ttf',
  ];
  for (final family in [
    'Segoe UI Variable Text',
    'Segoe UI Variable Display',
    'Segoe UI',
  ]) {
    await _loadFont(family, segoe);
  }
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot != null) {
    await _loadFont('MaterialIcons', [
      '$flutterRoot\\bin\\cache\\artifacts\\material_fonts\\MaterialIcons-Regular.otf',
    ]);
  }
}

void _write(String rel, {int size = 0, int seed = 0, int? ageDays}) {
  final f = File('$profile\\$rel')..parent.createSync(recursive: true);
  if (size > 4 * 1024 * 1024) {
    // Large files: set the length without writing the bytes.
    final raf = f.openSync(mode: FileMode.write);
    raf.truncateSync(size);
    raf.closeSync();
  } else {
    f.writeAsBytesSync(List.generate(size, (i) => (i * 7 + seed) & 0xFF));
  }
  if (ageDays != null) {
    f.setLastModifiedSync(DateTime.now().subtract(Duration(days: ageDays)));
  }
}

/// A photo-like picture with grain, so JPEGs have realistic sizes.
img.Image _photo(int seed, int w, int h, {double tintR = 0}) {
  final rnd = math.Random(seed);
  final blobs = [
    for (var k = 0; k < 7; k++)
      [
        rnd.nextDouble(), rnd.nextDouble(), 0.08 + rnd.nextDouble() * 0.15,
        rnd.nextDouble() * 255, rnd.nextDouble() * 255, rnd.nextDouble() * 255,
      ],
  ];
  final grain = math.Random(seed + 1000);
  final out = img.Image(width: w, height: h);
  for (var py = 0; py < h; py++) {
    for (var px = 0; px < w; px++) {
      final x = px / w, y = py / h;
      var r = 40 + 120 * x, g = 60 + 100 * y, b = 90 + 60 * (1 - x);
      for (final o in blobs) {
        final d = math.sqrt((x - o[0]) * (x - o[0]) + (y - o[1]) * (y - o[1]));
        final a = (1 - ((d - o[2]) / 0.03)).clamp(0.0, 1.0);
        r = r * (1 - a) + o[3] * a;
        g = g * (1 - a) + o[4] * a;
        b = b * (1 - a) + o[5] * a;
      }
      final n = grain.nextInt(25) - 12;
      out.setPixelRgb(
        px,
        py,
        (r + tintR + n).clamp(0.0, 255.0).round(),
        (g + n).clamp(0.0, 255.0).round(),
        (b + n).clamp(0.0, 255.0).round(),
      );
    }
  }
  return out;
}

void _writePhoto(String rel, img.Image image, int quality, int ageDays) {
  final f = File('$profile\\$rel')..parent.createSync(recursive: true);
  f.writeAsBytesSync(img.encodeJpg(image, quality: quality));
  f.setLastModifiedSync(DateTime.now().subtract(Duration(days: ageDays)));
}

void _buildDemoProfile() {
  final d = Directory(demoRoot);
  if (d.existsSync()) d.deleteSync(recursive: true);
  const mb = 1024 * 1024;
  _write(r'Downloads\TeamsSetup_x64.exe', size: 3 * mb, seed: 1, ageDays: 420);
  _write(r'Downloads\node-v18.17.0-x64.msi', size: 2 * mb, seed: 2, ageDays: 610);
  _write(r'Downloads\Q3 offsite photos.zip', size: 4 * mb, seed: 3, ageDays: 300);
  _write(r'Downloads\Invoice-2023-114.pdf', size: 2 * mb, seed: 7, ageDays: 700);
  _write(r'Documents\Projects\Atlas\Atlas proposal v2.docx',
      size: 2 * mb, seed: 4, ageDays: 260);
  _write(r'Documents\Taxes\Invoice-2023-114.pdf', size: 2 * mb, seed: 7, ageDays: 720);
  _write(r'Documents\Old drafts\Atlas proposal v2.docx',
      size: 2 * mb, seed: 4, ageDays: 255);
  _write(r'Desktop\screen-recording-2024-03-02.mp4',
      size: 900 * mb, ageDays: 400);
  _write(r'Videos\Family\Goa trip 2023.mov', size: 1800 * mb, ageDays: 650);
  _write(r'Pictures\Camera Roll\IMG_2041.jpg', size: 3 * mb, seed: 5, ageDays: 500);
  _write(r'Pictures\Camera Roll\IMG_2042.jpg', size: 3 * mb, seed: 6, ageDays: 500);
  _write(r'Music\Podcasts\episode-112.mp3', size: 3 * mb, seed: 8, ageDays: 380);
  _write(r'Documents\notes.txt', size: 2000, seed: 9, ageDays: 3);

  final beach = _photo(21, 1600, 1200);
  _writePhoto(r'Pictures\Goa\IMG_3001.jpg', beach, 92, 400);
  _writePhoto(r'Downloads\IMG_3001-WA0004.jpg',
      img.copyResize(beach, width: 1024, interpolation: img.Interpolation.average),
      75, 390);
  final market = _photo(33, 1600, 1200);
  _writePhoto(r'Pictures\Goa\IMG_3017.jpg', market, 92, 398);
  _writePhoto(r'Pictures\Goa\IMG_3017 (edited).jpg',
      _photo(33, 1600, 1200, tintR: 45), 90, 120);
  _writePhoto(r'Pictures\Goa\IMG_3020.jpg', _photo(47, 1600, 1200), 92, 397);
}

Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screenshots/$name.png'),
  );
}

Future<void> _open(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).first);
  await tester.pumpAndSettle();
}

void main() {
  late AppController c;

  setUpAll(() async {
    await _loadFonts();
    _buildDemoProfile();
    c = AppController.open(
      dataDirOverride: '$demoRoot\\appdata',
      foldersOverride: const KnownFolders(
        userProfile: profile,
        downloads: '$profile\\Downloads',
        documents: '$profile\\Documents',
        desktop: '$profile\\Desktop',
        pictures: '$profile\\Pictures',
        videos: '$profile\\Videos',
        music: '$profile\\Music',
      ),
      includeOtherDrives: false,
    );
    Scanner(
      fs: c.fs,
      db: c.db,
      categorizer: c.categorizer,
      clock: AppController.clock,
    ).run(ScanRequest(
      roots: c.scanRoots,
      trashRoots: c.trashRoots,
      protectedRoots: c.protectedRoots,
    ));
    DuplicateFinder(fs: c.fs, db: c.db, clock: AppController.clock)
        .run(minSize: c.settings.duplicateMin.bytes);
    // Something in the trash.
    final pod = c.db.byPath('$profile\\Music\\Podcasts\\episode-112.mp3');
    if (pod != null) c.moveToTrash([pod.id]);
  });

  Future<void> pumpApp(WidgetTester tester, Brightness b) async {
    await tester.binding.setSurfaceSize(const Size(1366, 860));
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(b),
      home: AppShell(controller: c),
    ));
  }

  testWidgets('light theme screens', (tester) async {
    await tester.runAsync(() => SimilarPhotoFinder(
          fs: c.fs,
          db: c.db,
          decoder: const FlutterImageDecoder(),
          clock: AppController.clock,
        ).run());
    await pumpApp(tester, Brightness.light);
    await _shot(tester, '1_overview_light');
    await _open(tester, 'Old files');
    await _shot(tester, '2_old_files_light');
    await _open(tester, 'Large files');
    await _shot(tester, '3_large_files_light');
    await _open(tester, 'Duplicates');
    await _shot(tester, '4_duplicates_light');
    await tester.tap(find.textContaining('Similar photos ('));
    await tester.pumpAndSettle();
    // Let the photo previews load: real time for the decoder, then frames.
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
    }
    await _shot(tester, '4b_similar_photos_light');
    await _open(tester, 'Trash');
    await _shot(tester, '5_trash_light');
    await _open(tester, 'Settings');
    await _shot(tester, '6_settings_light');
  });

  testWidgets('dark theme overview and old files', (tester) async {
    await pumpApp(tester, Brightness.dark);
    await _shot(tester, '7_overview_dark');
    await _open(tester, 'Old files');
    await _shot(tester, '8_old_files_dark');
  });
}
