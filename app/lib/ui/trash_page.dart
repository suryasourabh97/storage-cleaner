import 'package:cleaner_core/cleaner_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../platform/windows/system_info.dart';
import '../services/app_controller.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/components.dart';
import 'widgets/confirm_dialogs.dart';

/// Trash (spec flows 6, 7, 8).
class TrashPage extends StatefulWidget {
  const TrashPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  final Set<int> _selected = {};
  bool _readyOnly = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePurgeRequest());
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
    _consumePurgeRequest();
  }

  /// Home's notice opens the Trash with the 30-day items preselected.
  void _consumePurgeRequest() {
    if (!mounted || !c.purgeReviewRequested) return;
    c.purgeReviewRequested = false;
    setState(() {
      _readyOnly = true;
      _selected
        ..clear()
        ..addAll(c.purge.check().ids);
    });
  }

  Future<void> _restoreSelected(List<TrashItem> items) async {
    var restored = 0;
    final failures = <String>[];
    for (final item in items) {
      var result = c.restore(item.record.id);
      if (result is RestoreConflict) {
        if (!mounted) return;
        final choice = await _askConflict(result.originalPath);
        if (choice == null) continue;
        result = c.restore(item.record.id, choice: choice);
      }
      switch (result) {
        case Restored():
          restored++;
        case RestoreFailed(:final reason):
          failures.add(
            '${winPath.basename(item.record.originalPath ?? item.record.path)} '
            '(${skipReasonLabel(reason)})',
          );
        case RestoreConflict():
          break;
      }
    }
    if (!mounted) return;
    setState(_selected.clear);
    final msg = StringBuffer('${plural(restored, 'file')} restored.');
    if (failures.isNotEmpty) {
      msg.write(' Not restored: ${failures.take(3).join(', ')}');
      if (failures.length > 3) msg.write(' and ${failures.length - 3} more');
      msg.write('.');
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toString())));
  }

  Future<RestoreChoice?> _askConflict(String original) {
    return showDialog<RestoreChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('That name is taken'),
        content: SizedBox(
          width: 480,
          child: Text(
            'There is already a file at\n$original\n\n'
            'Keep both (the restored file gets a number added), or restore it '
            'into another folder.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip'),
          ),
          OutlinedButton(
            onPressed: () async {
              final dir = await getDirectoryPath(
                confirmButtonText: 'Restore here',
              );
              if (!context.mounted) return;
              Navigator.pop(context, dir == null ? null : RestoreInto(dir));
            },
            child: const Text('Choose folder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, const KeepBoth()),
            child: const Text('Keep both'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteForever(List<TrashItem> items) async {
    final available = [for (final i in items) if (i.available) i];
    if (available.isEmpty) return;
    final ok = await confirmPermanentDelete(context, [
      for (final i in available) ConfirmItem(i.record.path, i.record.size),
    ]);
    if (!ok || !mounted) return;
    // The token is minted only here, after the user confirmed (ADR-006).
    final confirmation = DeletionConfirmation.userConfirmed([
      for (final i in available) i.record.path,
    ]);
    final result = c.deletePermanently(
      [for (final i in available) i.record.id],
      confirmation,
    );
    if (!mounted) return;
    setState(_selected.clear);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summarizeBatch(result, 'deleted permanently'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final all = c.trashList();
    final items =
        _readyOnly ? [for (final i in all) if (i.purgeReady) i] : all;
    final ready = all.where((i) => i.purgeReady).length;
    final total = all.fold<int>(0, (s, i) => s + i.record.size);
    final chosen = [
      for (final i in items)
        if (_selected.contains(i.record.id)) i,
    ];
    final chosenBytes = chosen.fold<int>(0, (s, i) => s + i.record.size);

    final header = PageHeader(
      title: 'Trash',
      subtitle: all.isEmpty
          ? 'Files you remove wait here for at least 30 days. '
              'They are deleted only when you confirm.'
          : '${plural(all.length, 'file')}, ${formatBytes(total)}. '
              'Files stay until you delete them; after 30 days they are '
              'marked ready to delete.',
      trailing: [
        if (ready > 0)
          FilterChip(
            label: Text('Ready to delete ($ready)'),
            selected: _readyOnly,
            onSelected: (v) => setState(() => _readyOnly = v),
          ),
        OutlinedButton.icon(
          onPressed: () =>
              openInExplorer(c.locator.trashRootFor(c.folders.userProfile)),
          icon: const Icon(Icons.folder_open_outlined, size: 18),
          label: const Text('Open folder'),
        ),
        if (all.isNotEmpty)
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: t.brick),
            onPressed: () => _deleteForever(all),
            child: const Text('Empty trash'),
          ),
      ],
    );

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const Divider(),
          Expanded(
            child: items.isEmpty
                ? const EmptyMessage(
                    title: 'Trash is empty',
                    body: 'Files you move to the trash from the other screens '
                        'appear here.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 8, bottom: 24),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _row(items[i]),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: chosen.isEmpty
          ? null
          : SelectionBar(
              summary: '${plural(chosen.length, 'file')} selected, '
                  '${formatBytes(chosenBytes)}',
              actions: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: t.paper),
                  onPressed: () => _deleteForever(chosen),
                  child: const Text('Delete permanently'),
                ),
                ReclaimButton(
                  label: 'Restore',
                  icon: Icons.restore,
                  onPressed: () => _restoreSelected(chosen),
                ),
              ],
            ),
    );
  }

  Widget _row(TrashItem item) {
    final r = item.record;
    final original = r.originalPath ?? r.path;
    final status = !item.available
        ? 'Its drive is not connected.'
        : item.purgeReady
            ? 'Ready to delete.'
            : 'Ready to delete in ${plural(item.daysLeft, 'day')}.';
    return FileRow(
      selected: _selected.contains(r.id),
      onChanged: item.available
          ? (v) => setState(() {
                if (v) {
                  _selected.add(r.id);
                } else {
                  _selected.remove(r.id);
                }
              })
          : null,
      title: winPath.basename(original),
      subtitle: 'From ${winPath.dirname(original)}',
      note: r.trashedAt == null
          ? status
          : 'Moved here ${formatDate(r.trashedAt!)}. $status',
      size: formatBytes(r.size),
    );
  }
}
