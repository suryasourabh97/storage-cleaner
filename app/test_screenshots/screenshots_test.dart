@TestOn('windows')
library;

// Renders every screen against a demo profile and writes PNGs with
// `flutter test test_screenshots --update-goldens`. CI publishes them to the
// `ci-screenshots` branch so the design can be reviewed without a Windows PC.

import 'dart:io';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage_cleaner/main.dart';
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
    await pumpApp(tester, Brightness.light);
    await _shot(tester, '1_overview_light');
    await _open(tester, 'Old files');
    await _shot(tester, '2_old_files_light');
    await _open(tester, 'Large files');
    await _shot(tester, '3_large_files_light');
    await _open(tester, 'Duplicates');
    await _shot(tester, '4_duplicates_light');
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
