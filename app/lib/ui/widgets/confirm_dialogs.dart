import 'package:flutter/material.dart';

import '../format.dart';

/// One line in a confirmation list.
final class ConfirmItem {
  const ConfirmItem(this.path, this.size);
  final String path;
  final int size;
}

/// "Move 142 files (3.8 GB) to trash?" with an expandable file list
/// (spec §11). Returns true only if the user pressed the action button.
Future<bool> confirmMoveToTrash(
  BuildContext context,
  List<ConfirmItem> items,
) async {
  final total = items.fold<int>(0, (s, i) => s + i.size);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        'Move ${plural(items.length, 'file')} (${formatBytes(total)}) to trash?',
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'They stay in the StorageCleaner Trash folder on the same drive '
              'for at least 30 days, and you can restore them any time. '
              'Nothing is deleted.',
            ),
            const SizedBox(height: 12),
            _ItemList(items: items),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Move to trash'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Strong confirmation for permanent deletion: irreversible wording, red
/// button, and Cancel is the default (autofocused) action.
Future<bool> confirmPermanentDelete(
  BuildContext context,
  List<ConfirmItem> items,
) async {
  final total = items.fold<int>(0, (s, i) => s + i.size);
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: scheme.error),
      title: Text(
        'Permanently delete ${plural(items.length, 'file')} '
        '(${formatBytes(total)})?',
      ),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "This can't be undone. These files will be gone for good.",
              style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _ItemList(items: items),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete permanently'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

class _ItemList extends StatelessWidget {
  const _ItemList({required this.items});
  final List<ConfirmItem> items;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text('Show ${plural(items.length, 'file')}'),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: items.length,
            itemBuilder: (context, i) => ListTile(
              dense: true,
              title: Text(
                items[i].path,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(formatBytes(items[i].size)),
            ),
          ),
        ),
      ],
    );
  }
}
