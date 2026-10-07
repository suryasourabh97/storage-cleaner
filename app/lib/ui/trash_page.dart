import 'package:cleaner_core/cleaner_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../platform/windows/system_info.dart';
import '../services/app_controller.dart';
import 'format.dart';
import 'widgets/confirm_dialogs.dart';

/// Trash screen (spec flows 6, 7, 8).
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

  /// Home's "ready to delete" banner opens the Trash with those items
  /// preselected.
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

  List<TrashItem> _visible(List<TrashItem> all) =>
      _readyOnly ? [for (final i in all) if (i.purgeReady) i] : all;

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
            '${winPath.basename(item.record.originalPath ?? item.record.path)}: '
            '${skipReasonLabel(reason)}',
          );
        case RestoreConflict():
          break;
      }
    }
    if (!mounted) return;
    setState(_selected.clear);
    final msg = StringBuffer('${plural(restored, 'file')} restored.');
    if (failures.isNotEmpty) {
      msg.write(' Not restored: ${failures.take(3).join('; ')}');
      if (failures.length > 3) msg.write(' and ${failures.length - 3} more');
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg.toString())));
  }

  Future<RestoreChoice?> _askConflict(String original) {
    return showDialog<RestoreChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A file with this name already exists'),
        content: Text(
          '$original\n\nKeep both (the restored file gets a number added), '
          'or restore into another folder?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () async {
              final dir = await getDirectoryPath(
                confirmButtonText: 'Restore here',
              );
              if (!context.mounted) return;
              Navigator.pop(context, dir == null ? null : RestoreInto(dir));
            },
            child: const Text('Choose folder…'),
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
      SnackBar(content: Text(summarizeBatch(result, 'permanently deleted'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = c.trashList();
    final items = _visible(all);
    final ready = all.where((i) => i.purgeReady).length;
    final chosen = [for (final i in items) if (_selected.contains(i.record.id)) i];
    final chosenBytes = chosen.fold<int>(0, (s, i) => s + i.record.size);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trash'),
        actions: [
          if (ready > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text('Ready to delete ($ready)'),
                selected: _readyOnly,
                onSelected: (v) => setState(() => _readyOnly = v),
              ),
            ),
          IconButton(
            tooltip: 'Open trash folder',
            icon: const Icon(Icons.folder_open),
            onPressed: () => openInExplorer(
              c.locator.trashRootFor(c.folders.userProfile),
            ),
          ),
          TextButton(
            onPressed: all.isEmpty ? null : () => _deleteForever(all),
            child: const Text('Empty trash'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Text(
                'Trash is empty.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            )
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) => _tile(items[i]),
            ),
      bottomNavigationBar: chosen.isEmpty
          ? null
          : BottomAppBar(
              child: Row(
                children: [
                  Text(
                    '${plural(chosen.length, 'file')} selected · '
                    '${formatBytes(chosenBytes)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _deleteForever(chosen),
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('Delete permanently'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _restoreSelected(chosen),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _tile(TrashItem item) {
    final r = item.record;
    final original = r.originalPath ?? r.path;
    final status = !item.available
        ? 'Drive not connected'
        : item.purgeReady
            ? 'Ready to delete'
            : '${plural(item.daysLeft, 'day')} left';
    return CheckboxListTile(
      value: _selected.contains(r.id),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: item.available
          ? (v) => setState(() {
                if (v == true) {
                  _selected.add(r.id);
                } else {
                  _selected.remove(r.id);
                }
              })
          : null,
      title: Text(winPath.basename(original), overflow: TextOverflow.ellipsis),
      subtitle: Text(
        'From ${winPath.dirname(original)}\n'
        'Trashed ${r.trashedAt == null ? '' : formatDate(r.trashedAt!)} · $status',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      secondary: Text(formatBytes(r.size)),
    );
  }
}
