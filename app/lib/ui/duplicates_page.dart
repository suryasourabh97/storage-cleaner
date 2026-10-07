import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/components.dart';
import 'similar_photos_view.dart';
import 'widgets/confirm_dialogs.dart';

/// Exact duplicates (spec flow 10). One copy per group is always kept.
class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key, required this.controller});
  final AppController controller;

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _Choice {
  _Choice(this.keepId, this.removeIds);
  int keepId;
  final Set<int> removeIds;
}

enum _Tab { identical, similar }

class _DuplicatesPageState extends State<DuplicatesPage> {
  _Tab _tab = _Tab.identical;
  List<DuplicateGroup> _groups = const [];
  final Map<String, _Choice> _choices = {};
  bool _busy = false;

  AppController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
    c.addListener(_onChanged);
  }

  @override
  void dispose() {
    c.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted || c.analyzing || c.scanning) {
      if (mounted) setState(() {});
      return;
    }
    setState(_load);
  }

  /// Loads groups; keeps the user's choices for groups that still exist and
  /// applies the keep rule to new ones.
  void _load() {
    _groups = c.duplicateGroupsList();
    final live = <String>{};
    for (final g in _groups) {
      live.add(g.hash);
      final ids = {for (final m in g.members) m.id};
      final prev = _choices[g.hash];
      if (prev != null && ids.contains(prev.keepId)) {
        prev.removeIds.retainAll(ids);
        prev.removeIds.remove(prev.keepId);
      } else {
        _choices[g.hash] = _Choice(
          g.suggestedKeep.id,
          {for (final id in ids) if (id != g.suggestedKeep.id) id},
        );
      }
    }
    _choices.removeWhere((k, _) => !live.contains(k));
  }

  int get _selectedCount =>
      _choices.values.fold(0, (s, ch) => s + ch.removeIds.length);

  int get _selectedBytes {
    var total = 0;
    for (final g in _groups) {
      total += g.size * (_choices[g.hash]?.removeIds.length ?? 0);
    }
    return total;
  }

  Future<void> _removeSelected() async {
    final removals = <DuplicateRemoval>[];
    final items = <ConfirmItem>[];
    for (final g in _groups) {
      final ch = _choices[g.hash]!;
      if (ch.removeIds.isEmpty) continue;
      // Never offer a selection without a kept copy (safety rule).
      if (!KeepRules.keepsAtLeastOne(
        g.members.map((m) => m.id),
        ch.removeIds,
      )) {
        continue;
      }
      removals.add(DuplicateRemoval(
        group: g,
        keepId: ch.keepId,
        removeIds: Set.of(ch.removeIds),
      ));
      for (final m in g.members.where((m) => ch.removeIds.contains(m.id))) {
        items.add(ConfirmItem(m.path, m.size));
      }
    }
    if (removals.isEmpty) return;
    final ok = await confirmMoveToTrash(context, items);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    final result = c.removeDuplicateCopies(removals);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summarizeBatch(result, 'moved to trash'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final latest = c.latestAnalysis;
    final reclaimable = _groups.fold(0, (s, g) => s + g.reclaimable);

    final String? subtitle;
    if (c.analyzing) {
      subtitle = 'Comparing files with the same size. Only files that might '
          'match are read.';
    } else if (_tab == _Tab.similar) {
      subtitle = 'Photos that are the same picture saved at another size or '
          'quality. The best-quality copy is kept; edited versions are left '
          'for you to choose.';
    } else if (latest == null) {
      subtitle = 'Finds files with exactly the same content, whatever their '
          'names. Files under ${minSizeLabel(c.settings.duplicateMin)} '
          'are skipped.';
    } else if (_groups.isEmpty) {
      subtitle = 'Checked ${formatDate(latest.$1)}.';
    } else {
      subtitle = '${plural(_groups.length, 'group')} of identical files, '
          '${formatBytes(reclaimable)} in extra copies. '
          'Checked ${formatDate(latest.$1)}.';
    }

    final header = PageHeader(
      title: 'Duplicates',
      subtitle: subtitle,
      trailing: [
        if (c.analyzing)
          OutlinedButton(onPressed: c.cancelScan, child: const Text('Stop'))
        else
          FilledButton.icon(
            onPressed: c.scanning || c.latestRun == null ? null : c.findDuplicates,
            icon: const Icon(Icons.difference_outlined, size: 18),
            label: Text(latest == null ? 'Find duplicates' : 'Check again'),
          ),
      ],
    );

    Widget body;
    if (c.analyzing) {
      final p = c.analysisProgress;
      final phase = switch (p?.phase) {
        AnalysisPhase.comparingSizes || null => 'Comparing sizes',
        AnalysisPhase.sampling => 'Checking the start, middle and end of files',
        AnalysisPhase.hashing => 'Comparing full contents',
        AnalysisPhase.fingerprinting => 'Looking at photos',
      };
      body = Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(
              minHeight: 3,
              value: p == null || p.total == 0 ? null : p.done / p.total,
            ),
            const SizedBox(height: 10),
            Text(
              p == null
                  ? 'Starting'
                  : p.phase == AnalysisPhase.fingerprinting
                      ? '$phase, ${p.done} of ${p.total}.'
                      : '$phase, ${p.done} of ${p.total}. '
                          '${formatBytes(p.bytesRead)} read.',
              style: text.bodyMedium?.copyWith(color: t.muted),
            ),
          ],
        ),
      );
    } else if (c.latestRun == null) {
      body = const EmptyMessage(
        title: 'Nothing scanned yet',
        body: 'Run a scan from Home first, then look for duplicates here.',
      );
    } else if (_tab == _Tab.similar) {
      body = SimilarPhotosView(controller: c);
    } else if (_groups.isEmpty) {
      body = EmptyMessage(
        title: latest == null ? 'Not checked yet' : 'No duplicates found',
        body: latest == null
            ? 'Checking reads only files that share a size with another file.'
            : 'No two files of ${minSizeLabel(c.settings.duplicateMin)} or more '
                'have the same content.',
      );
    } else {
      final rows = <Widget Function()>[];
      for (final g in _groups) {
        rows.add(() => _groupHeading(g));
        for (final m in g.members) {
          rows.add(() => _memberRow(g, m));
        }
      }
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: rows.length,
        itemBuilder: (context, i) => rows[i](),
      );
    }

    final count = _selectedCount;
    final similarCount = c.analyzing ? 0 : c.similarGroupsList().length;
    final tabs = Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<_Tab>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: _Tab.identical,
              label: Text('Identical files (${_groups.length})'),
            ),
            ButtonSegment(
              value: _Tab.similar,
              enabled: c.settings.similarPhotos,
              label: Text(
                c.settings.similarPhotos
                    ? 'Similar photos ($similarCount)'
                    : 'Similar photos (off in Settings)',
              ),
            ),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
      ),
    );
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, tabs, const Divider(), Expanded(child: body)],
      ),
      bottomNavigationBar: count == 0 || c.analyzing || _tab == _Tab.similar
          ? null
          : SelectionBar(
              summary: '${plural(count, 'extra copy', 'extra copies')} selected, '
                  '${formatBytes(_selectedBytes)}. One copy of each file is kept.',
              actions: [
                ReclaimButton(
                  label: 'Move extra copies to trash',
                  onPressed: _busy ? null : _removeSelected,
                ),
              ],
            ),
    );
  }

  Widget _groupHeading(DuplicateGroup g) {
    return GroupHeading(
      title: winPath.basename(g.suggestedKeep.path),
      detail: '${g.members.length} copies of ${formatBytes(g.size)}, '
          '${formatBytes(g.reclaimable)} in extra copies',
    );
  }

  Widget _memberRow(DuplicateGroup g, FileRecord m) {
    final ch = _choices[g.hash]!;
    final keeping = ch.keepId == m.id;
    final t = context.tokens;
    return FileRow(
      selected: ch.removeIds.contains(m.id),
      dimmed: false,
      onChanged: keeping
          ? null
          : (v) => setState(() {
                if (v) {
                  ch.removeIds.add(m.id);
                } else {
                  ch.removeIds.remove(m.id);
                }
              }),
      leading: keeping
          ? Tooltip(
              message: 'This copy is kept',
              child: Icon(Icons.push_pin, size: 18, color: t.amber),
            )
          : null,
      title: m.path,
      subtitle: 'Modified ${formatDate(m.modified)}'
          '${m.cloudSynced ? '. In OneDrive.' : ''}',
      size: formatBytes(m.size),
      trailing: keeping
          ? Text(
              'Kept',
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.labelLarge,
            )
          : Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() {
                  final previous = ch.keepId;
                  ch.keepId = m.id;
                  ch.removeIds
                    ..remove(m.id)
                    ..add(previous);
                }),
                child: const Text('Keep this one'),
              ),
            ),
    );
  }
}
