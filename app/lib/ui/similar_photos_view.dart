import 'dart:io';

import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';

import '../services/app_controller.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/components.dart';
import 'widgets/confirm_dialogs.dart';

/// Similar photos (spec flow 11): side-by-side previews; the best-quality
/// copy is kept; groups with an edited copy start with nothing selected.
class SimilarPhotosView extends StatefulWidget {
  const SimilarPhotosView({super.key, required this.controller});
  final AppController controller;

  @override
  State<SimilarPhotosView> createState() => _SimilarPhotosViewState();
}

class _Choice {
  _Choice(this.keepId, this.removeIds);
  int keepId;
  final Set<int> removeIds;
}

class _SimilarPhotosViewState extends State<SimilarPhotosView> {
  List<SimilarGroup> _groups = const [];
  final Map<int, _Choice> _choices = {}; // keyed by the group's best photo
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
    if (!mounted || c.analyzing || c.scanning) return;
    setState(_load);
  }

  void _load() {
    _groups = c.similarGroupsList();
    final live = <int>{};
    for (final g in _groups) {
      final key = g.best.id;
      live.add(key);
      final ids = {for (final m in g.members) m.id};
      final prev = _choices[key];
      if (prev != null && ids.contains(prev.keepId)) {
        prev.removeIds
          ..retainAll(ids)
          ..remove(prev.keepId);
      } else {
        _choices[key] = _Choice(g.best.id, Set.of(g.defaultRemovals));
      }
    }
    _choices.removeWhere((k, _) => !live.contains(k));
  }

  int get _selectedCount =>
      _choices.values.fold(0, (s, ch) => s + ch.removeIds.length);

  int get _selectedBytes {
    var total = 0;
    for (final g in _groups) {
      final ch = _choices[g.best.id]!;
      for (final m in g.members) {
        if (ch.removeIds.contains(m.id)) total += m.size;
      }
    }
    return total;
  }

  Future<void> _removeSelected() async {
    final removals = <SimilarRemoval>[];
    final items = <ConfirmItem>[];
    for (final g in _groups) {
      final ch = _choices[g.best.id]!;
      if (ch.removeIds.isEmpty) continue;
      if (!KeepRules.keepsAtLeastOne(
        g.members.map((m) => m.id),
        ch.removeIds,
      )) {
        continue;
      }
      removals.add(SimilarRemoval(
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
    final result = c.removeSimilarCopies(removals);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summarizeBatch(result, 'moved to trash'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final latest = c.latestSimilar;
    final s = c.lastSimilar;
    if (_groups.isEmpty) {
      return EmptyMessage(
        title: latest == null ? 'Photos not checked yet' : 'No similar photos',
        body: latest == null
            ? 'Use "Find duplicates" above. Photos are compared from small '
                'previews; only new or changed photos are looked at again.'
            : 'No two photos look like copies of each other.'
                '${s != null && s.unsupported > 0 ? ' ${plural(s.unsupported, 'HEIC photo')} could not be checked yet.' : ''}',
      );
    }
    final count = _selectedCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: _groups.length + (s != null && s.unsupported > 0 ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == _groups.length) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
                  child: Text(
                    '${plural(s!.unsupported, 'HEIC photo')} could not be '
                    'checked yet; this format is not supported in this version.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              }
              return _group(_groups[i]);
            },
          ),
        ),
        if (count > 0)
          SelectionBar(
            summary: '${plural(count, 'photo')} selected, '
                '${formatBytes(_selectedBytes)}. The kept photo in each group '
                'stays.',
            actions: [
              ReclaimButton(
                label: 'Move to trash',
                onPressed: _busy ? null : _removeSelected,
              ),
            ],
          ),
      ],
    );
  }

  Widget _group(SimilarGroup g) {
    final ch = _choices[g.best.id]!;
    final t = context.tokens;
    final detail = g.edited
        ? 'Includes an edited version, so nothing is selected. Choose what to remove.'
        : '${plural(g.members.length, 'copy', 'copies')}, '
            '${formatBytes(g.reclaimable)} in smaller copies';
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                winPath.basename(g.best.path),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: g.edited ? t.ink : t.muted,
                        fontStyle: g.edited ? FontStyle.italic : null,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final m in g.members)
                _PhotoCard(
                  record: m,
                  kept: ch.keepId == m.id,
                  selected: ch.removeIds.contains(m.id),
                  onToggle: (v) => setState(() {
                    if (v) {
                      ch.removeIds.add(m.id);
                    } else {
                      ch.removeIds.remove(m.id);
                    }
                  }),
                  onKeep: () => setState(() {
                    ch.keepId = m.id;
                    ch.removeIds.remove(m.id);
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PhotoCard extends StatelessWidget {
  const _PhotoCard({
    required this.record,
    required this.kept,
    required this.selected,
    required this.onToggle,
    required this.onKeep,
  });

  final FileRecord record;
  final bool kept;
  final bool selected;
  final ValueChanged<bool> onToggle;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final borderColor = kept
        ? t.ink
        : selected
            ? t.amber
            : t.line;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: borderColor, width: kept || selected ? 2 : 1),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: t.paper,
              child: Image.file(
                File(record.path),
                cacheWidth: 440,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) =>
                    Icon(Icons.image_not_supported_outlined, color: t.muted),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.width ?? '?'} × ${record.height ?? '?'}',
                  style: sizeText(context),
                ),
                Text(formatBytes(record.size), style: text.bodySmall),
                const SizedBox(height: 4),
                Tooltip(
                  message: record.path,
                  child: Text(
                    record.path,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 8, 6),
            child: kept
                ? Row(
                    children: [
                      const SizedBox(width: 8),
                      Icon(Icons.push_pin, size: 16, color: t.amber),
                      const SizedBox(width: 6),
                      Text('Kept', style: text.labelLarge),
                    ],
                  )
                : Row(
                    children: [
                      Checkbox(
                        value: selected,
                        onChanged: (v) => onToggle(v ?? false),
                      ),
                      Text('Remove', style: text.bodyMedium),
                      const Spacer(),
                      TextButton(onPressed: onKeep, child: const Text('Keep this')),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
