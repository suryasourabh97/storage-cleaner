import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'format.dart';
import 'widgets/confirm_dialogs.dart';

enum FilesKind { old, large }

/// Old Files and Large Files screens (spec flows 3, 4, 9).
class FilesPage extends StatefulWidget {
  const FilesPage({super.key, required this.controller, required this.kind});

  final AppController controller;
  final FilesKind kind;

  @override
  State<FilesPage> createState() => _FilesPageState();
}

sealed class _Row {}

final class _Header extends _Row {
  _Header(this.label, this.items);
  final String label;
  final List<Candidate> items;
}

final class _FileRow extends _Row {
  _FileRow(this.c);
  final Candidate c;
}

class _FilesPageState extends State<FilesPage> {
  List<Candidate> _items = const [];
  final Set<int> _selected = {};
  String _loadedFor = '';
  bool _busy = false;

  AppController get c => widget.controller;

  String get _thresholdKey => widget.kind == FilesKind.old
      ? c.settings.age.name
      : c.settings.size.name;

  @override
  void initState() {
    super.initState();
    _load(resetSelection: true);
    c.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(FilesPage old) {
    super.didUpdateWidget(old);
    if (old.kind != widget.kind) _load(resetSelection: true);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (c.scanning) return; // reload once the scan is done
    _reload(resetSelection: _thresholdKey != _loadedFor);
  }

  void _reload({required bool resetSelection}) =>
      setState(() => _load(resetSelection: resetSelection));

  void _load({required bool resetSelection}) {
    final items = widget.kind == FilesKind.old
        ? c.oldFilesList()
        : c.largeFilesList();
    _items = items;
    final ids = {for (final i in items) i.record.id};
    if (resetSelection) {
      _selected
        ..clear()
        ..addAll([
          for (final i in items)
            if (i.preselected && _selectable(i)) i.record.id,
        ]);
    } else {
      _selected.retainAll(ids);
    }
    _loadedFor = _thresholdKey;
  }

  /// OneDrive "Free up space" arrives in a later milestone; until then those
  /// files are shown but can't be selected.
  bool _selectable(Candidate i) => i.action == CandidateAction.trash;

  List<_Row> _rows() {
    if (widget.kind == FilesKind.large) {
      return [for (final i in _items) _FileRow(i)];
    }
    final groups = <Category, List<Candidate>>{};
    for (final i in _items) {
      groups.putIfAbsent(i.record.category, () => []).add(i);
    }
    final ordered = groups.entries.toList()
      ..sort((a, b) => _bytes(b.value).compareTo(_bytes(a.value)));
    return [
      for (final g in ordered) ...[
        _Header(categoryLabel(g.key), g.value),
        for (final i in g.value) _FileRow(i),
      ],
    ];
  }

  static int _bytes(Iterable<Candidate> c) =>
      c.fold(0, (s, x) => s + x.record.size);

  int get _selectedBytes =>
      _bytes(_items.where((i) => _selected.contains(i.record.id)));

  Future<void> _moveSelected() async {
    final chosen =
        _items.where((i) => _selected.contains(i.record.id)).toList();
    if (chosen.isEmpty) return;
    final ok = await confirmMoveToTrash(context, [
      for (final i in chosen) ConfirmItem(i.record.path, i.record.size),
    ]);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = c.moveToTrash([for (final i in chosen) i.record.id]);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summarizeBatch(result, 'moved to trash'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    final title = widget.kind == FilesKind.old ? 'Old files' : 'Large files';
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: widget.kind == FilesKind.old
                ? _ThresholdPicker<AgeThreshold>(
                    label: 'Not modified for',
                    value: c.settings.age,
                    values: AgeThreshold.values,
                    labelOf: ageLabel,
                    onChanged: c.setAge,
                  )
                : _ThresholdPicker<SizeThreshold>(
                    label: 'At least',
                    value: c.settings.size,
                    values: SizeThreshold.values,
                    labelOf: sizeLabel,
                    onChanged: c.setSize,
                  ),
          ),
        ],
      ),
      body: c.latestRun == null
          ? const _EmptyState(
              icon: Icons.search,
              text: 'Run a scan from Home to find files.',
            )
          : rows.isEmpty
              ? _EmptyState(
                  icon: Icons.check_circle_outline,
                  text: widget.kind == FilesKind.old
                      ? 'No files older than ${ageLabel(c.settings.age)}.'
                      : 'No files of ${sizeLabel(c.settings.size)} or more.',
                )
              : ListView.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) => switch (rows[i]) {
                    _Header h => _headerTile(h),
                    _FileRow f => _fileTile(f.c),
                  },
                ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : BottomAppBar(
              child: Row(
                children: [
                  Text(
                    '${plural(_selected.length, 'file')} selected · '
                    '${formatBytes(_selectedBytes)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear selection'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _moveSelected,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Move to trash'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _headerTile(_Header h) {
    final selectable = h.items.where(_selectable).toList();
    final selectedCount =
        selectable.where((i) => _selected.contains(i.record.id)).length;
    final bool? state = selectedCount == 0
        ? false
        : selectedCount == selectable.length
            ? true
            : null;
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: CheckboxListTile(
        tristate: true,
        value: state,
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          h.label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        secondary: Text(
          '${plural(h.items.length, 'file')} · ${formatBytes(_bytes(h.items))}',
        ),
        onChanged: selectable.isEmpty
            ? null
            : (_) => setState(() {
                  final ids = [for (final i in selectable) i.record.id];
                  if (state == true) {
                    _selected.removeAll(ids);
                  } else {
                    _selected.addAll(ids);
                  }
                }),
      ),
    );
  }

  Widget _fileTile(Candidate i) {
    final r = i.record;
    final name = winPath.basename(r.path);
    final folder = winPath.dirname(r.path);
    final selectable = _selectable(i);
    final notes = <String>[
      'Modified ${formatDate(r.modified)}',
      if (r.isProtected) 'Picture — unselected by default',
      if (r.pinned) 'Always kept on this device',
      if (!selectable) 'OneDrive — "Free up space" coming in a later update',
    ];
    return CheckboxListTile(
      value: _selected.contains(r.id),
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: selectable
          ? (v) => setState(() {
                if (v == true) {
                  _selected.add(r.id);
                } else {
                  _selected.remove(r.id);
                }
              })
          : null,
      title: Text(name, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '$folder\n${notes.join(' · ')}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: true,
      secondary: Text(formatBytes(r.size)),
    );
  }
}

class _ThresholdPicker<T> extends StatelessWidget {
  const _ThresholdPicker({
    required this.label,
    required this.value,
    required this.values,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> values;
  final String Function(T) labelOf;
  final void Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label '),
        DropdownButton<T>(
          value: value,
          underline: const SizedBox.shrink(),
          items: [
            for (final v in values)
              DropdownMenuItem<T>(value: v, child: Text(labelOf(v))),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(text, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}
