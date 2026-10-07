import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storage_cleaner/ui/theme.dart';
import 'package:storage_cleaner/ui/widgets/components.dart';
import 'package:storage_cleaner/ui/widgets/confirm_dialogs.dart';
import 'package:storage_cleaner/ui/widgets/storage_bar.dart';

Widget _wrap(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
      theme: buildTheme(b),
      home: Scaffold(body: child),
    );

void main() {
  for (final b in Brightness.values) {
    testWidgets('storage bar and legend render ($b)', (tester) async {
      await tester.pumpWidget(_wrap(
        const Padding(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              StorageBar(total: 1000, used: 700, reclaimable: 200),
              StorageBar(total: 0, used: 0, reclaimable: 0, height: 14),
            ],
          ),
        ),
        b: b,
      ));
      expect(find.byType(StorageBar), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('file row toggles selection when tapped', (tester) async {
    var selected = false;
    await tester.pumpWidget(_wrap(StatefulBuilder(
      builder: (context, setState) => FileRow(
        selected: selected,
        onChanged: (v) => setState(() => selected = v),
        title: 'report.pdf',
        subtitle: r'C:\Users\me\Downloads',
        note: 'In Pictures, so not selected automatically.',
        size: '1.5 MB',
      ),
    )));
    await tester.tap(find.text('report.pdf'));
    await tester.pump();
    expect(selected, isTrue);
  });

  testWidgets('page header, selection bar and empty message lay out',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 800));
    await tester.pumpWidget(_wrap(Column(
      children: [
        PageHeader(
          title: 'Old files',
          subtitle: '12 files, 3.8 GB in all.',
          trailing: [
            InlineDropdown<int>(
              label: 'At least',
              value: 1,
              values: const [1, 2],
              labelOf: (v) => '$v GB',
              onChanged: (_) {},
            ),
          ],
        ),
        const Expanded(
          child: EmptyMessage(title: 'Nothing scanned yet', body: 'Run a scan.'),
        ),
        SelectionBar(
          summary: '2 files selected, 3 MB',
          actions: [ReclaimButton(label: 'Move to trash', onPressed: () {})],
        ),
      ],
    )));
    expect(find.text('Move to trash'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('permanent delete dialog defaults to Cancel', (tester) async {
    bool? result;
    await tester.pumpWidget(_wrap(Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          result = await confirmPermanentDelete(
            context,
            const [ConfirmItem(r'C:\a.txt', 10)],
          );
        },
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete permanently'), findsOneWidget);
    // Enter activates the focused (Cancel) button.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
