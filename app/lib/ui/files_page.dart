import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'format.dart';
import 'widgets/components.dart';
import 'widgets/confirm_dialogs.dart';

enum FilesKind { old, large }

/// Old files and Large files (spec flows 3, 4, 9).
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
  bool get _old => widget.kind == FilesKind.old;

  String get _thresholdKey => _old ? c.settings.age.name : c.settings.size.name;

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
    if (c.scanning || !mounted) return;
    setState(() => _load(resetSelection: _thresholdKey != _loadedFor));
  }

  void _load({required bool resetSelection}) {
    final items = _old ? c.oldFilesList() : c.largeFilesList();
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
    if (!_old) return [for (final i in _items) _FileRow(i)];
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
    final total = _bytes(_items);
    final header = PageHeader(
      title: _old ? 'Old files' : 'Large files',
      subtitle: c.latestRun == null
          ? null
          : _items.isEmpty
              ? null
              : '${plural(_items.length, 'file')}, ${formatBytes(total)} in all. '
                  '${_old ? 'Pictures start unselected.' : 'Files changed this week start unselected.'}',
      trailing: [
        if (_old)
          InlineDropdown<AgeThreshold>(
            label: 'Not modified for',
            value: c.settings.age,
            values: AgeThreshold.values,
            labelOf: ageLabel,
            onChanged: c.setAge,
          )
        else
          InlineDropdown<SizeThreshold>(
            label: 'At least',
            value: c.settings.size,
            values: SizeThreshold.values,
            labelOf: sizeLabel,
            onChanged: c.setSize,
          ),
      ],
    );

    final Widget body;
    if (c.latestRun == null) {
      body = const EmptyMessage(
        title: 'Nothing scanned yet',
        body: 'Run a scan from Home to see your files here.',
      );
    } else if (rows.isEmpty) {
      body = EmptyMessage(
        title: _old ? 'No old files' : 'No large files',
        body: _old
            ? 'Nothing has gone unmodified for ${ageLabel(c.settings.age)}. '
                'Try a shorter period.'
            : 'No file is ${sizeLabel(c.settings.size)} or bigger. '
                'Try a smaller size.',
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: rows.length,
        itemBuilder: (context, i) => switch (rows[i]) {
          _Header h => _headerRow(h),
          _FileRow f => _fileRow(f.c),
        },
      );
    }

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const Divider(), Expanded(child: body)],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SelectionBar(
              summary: '${plural(_selected.length, 'file')} selected, '
                  '${formatBytes(_selectedBytes)}',
              actions: [
                BarTextButton(
                  label: 'Clear selection',
                  onPressed: () => setState(_selected.clear),
                ),
                ReclaimButton(
                  label: 'Move to trash',
                  onPressed: _busy ? null : _moveSelected,
                ),
              ],
            ),
    );
  }

  Widget _headerRow(_Header h) {
    final selectable = h.items.where(_selectable).toList();
    final selectedCount =
        selectable.where((i) => _selected.contains(i.record.id)).length;
    final bool? state = selectedCount == 0
        ? false
        : selectedCount == selectable.length
            ? true
            : null;
    return GroupHeading(
      title: h.label,
      detail: '${plural(h.items.length, 'file')}, ${formatBytes(_bytes(h.items))}',
      checkbox: Checkbox(
        tristate: true,
        value: state,
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

  Widget _fileRow(Candidate i) {
    final r = i.record;
    final selectable = _selectable(i);
    final String? note;
    if (!selectable) {
      note = 'In OneDrive. Freeing local space is coming in a later update.';
    } else if (r.isProtected) {
      note = 'In Pictures, so not selected automatically.';
    } else if (r.pinned) {
      note = 'Set to always stay on this device.';
    } else {
      note = null;
    }
    return FileRow(
      selected: _selected.contains(r.id),
      onChanged: selectable
          ? (v) => setState(() {
                if (v) {
                  _selected.add(r.id);
                } else {
                  _selected.remove(r.id);
                }
              })
          : null,
      title: winPath.basename(r.path),
      subtitle: '${winPath.dirname(r.path)}    modified ${formatDate(r.modified)}',
      note: note,
      size: formatBytes(r.size),
    );
  }
}
