import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';

import '../platform/windows/system_info.dart';
import '../services/app_controller.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/storage_bar.dart';

/// Home: how much can be reclaimed, per drive, and where it is.
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onOpenOld,
    required this.onOpenLarge,
    required this.onOpenDuplicates,
    required this.onOpenTrash,
  });

  final AppController controller;
  final VoidCallback onOpenOld;
  final VoidCallback onOpenLarge;
  final VoidCallback onOpenDuplicates;
  final VoidCallback onOpenTrash;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final run = c.latestRun;
        final busy = c.scanning || c.analyzing;
        final overview = busy || run == null ? null : c.overview();
        final text = Theme.of(context).textTheme;
        final t = context.tokens;
        return ListView(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 40),
          children: [
            if (overview != null && !overview.purgeReady.isEmpty) ...[
              _PurgeNotice(
                summary: overview.purgeReady,
                onReview: () {
                  c.purgeReviewRequested = true;
                  onOpenTrash();
                },
              ),
              const SizedBox(height: 24),
            ],

            // Headline figure + scan control.
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: overview == null
                      ? Text(
                          run == null
                              ? 'See what you can clean up'
                              : 'Scanning your folders',
                          style: text.displaySmall,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatBytes(overview.reclaimableTotal),
                              style: figure(context, size: 56),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'can be reclaimed after you review it',
                              style: text.bodyLarge?.copyWith(color: t.muted),
                            ),
                          ],
                        ),
                ),
                if (c.scanning)
                  OutlinedButton(
                    onPressed: c.cancelScan,
                    child: const Text('Stop scan'),
                  )
                else
                  FilledButton.icon(
                    onPressed: c.analyzing ? null : c.scan,
                    icon: const Icon(Icons.search, size: 18),
                    label: Text(run == null ? 'Scan my files' : 'Scan again'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _ScanStatus(controller: c, run: run),
            const SizedBox(height: 28),

            // Drives.
            for (final d in c.drives) ...[
              _DriveMeter(
                drive: d,
                reclaimable:
                    overview?.reclaimableByDrive[d.root.toUpperCase()] ?? 0,
                primary: d == c.drives.first,
              ),
              const SizedBox(height: 20),
            ],

            if (overview != null) ...[
              const SizedBox(height: 12),
              Text('Where the space is', style: text.headlineSmall),
              const SizedBox(height: 8),
              const Divider(),
              _LedgerRow(
                title: 'Old files',
                detail: 'Not modified for ${ageLabel(c.settings.age)}',
                count: plural(overview.oldCount, 'file'),
                bytes: overview.oldBytes,
                onTap: onOpenOld,
              ),
              _LedgerRow(
                title: 'Large files',
                detail: '${sizeLabel(c.settings.size)} or bigger, any age',
                count: plural(overview.largeCount, 'file'),
                bytes: overview.largeBytes,
                onTap: onOpenLarge,
              ),
              _LedgerRow(
                title: 'Duplicates',
                detail: c.latestAnalysis == null
                    ? 'Not checked yet'
                    : 'Extra copies of identical files',
                count: plural(overview.duplicateGroups, 'group'),
                bytes: overview.duplicateBytes,
                onTap: onOpenDuplicates,
              ),
              _LedgerRow(
                title: 'Trash',
                detail: 'Recoverable for at least 30 days',
                count: plural(overview.trashCount, 'file'),
                bytes: overview.trashBytes,
                onTap: onOpenTrash,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ScanStatus extends StatelessWidget {
  const _ScanStatus({required this.controller, required this.run});
  final AppController controller;
  final ScanRun? run;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = context.tokens;
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: t.muted,
        );
    if (c.scanning) {
      final p = c.progress;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(minHeight: 3),
          const SizedBox(height: 8),
          Text(
            p == null
                ? 'Starting. Scanning reads names, sizes and dates only.'
                : '${plural(p.files, 'file')} checked so far, now in ${p.currentDir}',
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    final r = run;
    final String line;
    if (c.scanError != null) {
      line = 'The scan stopped: ${c.scanError}. Try scanning again.';
    } else if (r == null) {
      line = 'Scanning reads file names, sizes and dates. Nothing is changed.';
    } else {
      final parts = [
        'Last scan ${formatDate(r.endedAt ?? r.startedAt)}, '
            '${plural(r.files, 'file')} checked.',
        if (r.status != RunStatus.complete)
          'It did not finish; scan again to complete it.',
        if (r.unreadableDirs > 0)
          '${plural(r.unreadableDirs, 'folder')} could not be read.',
      ];
      line = parts.join(' ');
    }
    return Text(line, style: style);
  }
}

class _DriveMeter extends StatelessWidget {
  const _DriveMeter({
    required this.drive,
    required this.reclaimable,
    required this.primary,
  });

  final DriveInfo drive;
  final int reclaimable;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    final name = drive.kind == DriveKind.removable
        ? '${drive.root} USB drive'
        : 'Drive ${drive.root}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(name, style: text.titleMedium),
            const Spacer(),
            Text(
              '${formatBytes(drive.freeBytes)} free of ${formatBytes(drive.totalBytes)}',
              style: text.bodyMedium?.copyWith(
                color: t.muted,
                fontFeatures: tabular,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        StorageBar(
          total: drive.totalBytes,
          used: drive.usedBytes,
          reclaimable: reclaimable,
          height: primary ? 28 : 14,
        ),
        if (primary) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: [
              LegendItem(
                label: 'Used',
                value: formatBytes(drive.usedBytes),
                swatch: t.ink,
              ),
              LegendItem(
                label: 'Reclaimable',
                value: formatBytes(reclaimable),
                swatch: t.amber,
                hatched: true,
              ),
              LegendItem(
                label: 'Free',
                value: formatBytes(drive.freeBytes),
                swatch: t.track,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.title,
    required this.detail,
    required this.count,
    required this.bytes,
    required this.onTap,
  });

  final String title;
  final String detail;
  final String count;
  final int bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(detail, style: text.bodySmall),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(
                    count,
                    style: text.bodyMedium?.copyWith(color: t.muted),
                    textAlign: TextAlign.end,
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Text(
                    formatBytes(bytes),
                    style: figure(context, size: 24),
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(Icons.chevron_right, color: t.muted),
              ],
            ),
          ),
        ),
        const Divider(),
      ],
    );
  }
}

class _PurgeNotice extends StatelessWidget {
  const _PurgeNotice({required this.summary, required this.onReview});
  final PurgeSummary summary;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(left: BorderSide(color: t.amber, width: 3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${plural(summary.count, 'file')} (${formatBytes(summary.bytes)}) '
              'have been in the trash for 30 days. They stay there until you '
              'choose to delete them.',
            ),
          ),
          TextButton(onPressed: onReview, child: const Text('Review')),
        ],
      ),
    );
  }
}
