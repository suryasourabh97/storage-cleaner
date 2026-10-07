import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/material.dart';

import '../platform/windows/system_info.dart';
import '../services/app_controller.dart';
import 'format.dart';

/// Home: disk usage, scan, and what can be reclaimed (spec §5.1).
class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.onOpenOld,
    required this.onOpenLarge,
    required this.onOpenTrash,
  });

  final AppController controller;
  final VoidCallback onOpenOld;
  final VoidCallback onOpenLarge;
  final VoidCallback onOpenTrash;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final run = c.latestRun;
        final overview = c.scanning || run == null ? null : c.overview();
        return Scaffold(
          appBar: AppBar(title: const Text('Storage Cleaner')),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (overview != null && !overview.purgeReady.isEmpty)
                _PurgeBanner(
                  summary: overview.purgeReady,
                  onReview: () {
                    c.purgeReviewRequested = true;
                    onOpenTrash();
                  },
                ),
              _DrivesCard(drives: c.drives),
              const SizedBox(height: 16),
              _ScanCard(controller: c, run: run),
              const SizedBox(height: 16),
              if (overview != null)
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _StatTile(
                      icon: Icons.history,
                      label:
                          'Old files (not modified for ${ageLabel(c.settings.age)})',
                      value: formatBytes(overview.oldBytes),
                      detail: plural(overview.oldCount, 'file'),
                      onTap: onOpenOld,
                    ),
                    _StatTile(
                      icon: Icons.sd_storage_outlined,
                      label: 'Large files (${sizeLabel(c.settings.size)}+)',
                      value: formatBytes(overview.largeBytes),
                      detail: plural(overview.largeCount, 'file'),
                      onTap: onOpenLarge,
                    ),
                    _StatTile(
                      icon: Icons.delete_outline,
                      label: 'In trash',
                      value: formatBytes(overview.trashBytes),
                      detail: plural(overview.trashCount, 'file'),
                      onTap: onOpenTrash,
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DrivesCard extends StatelessWidget {
  const _DrivesCard({required this.drives});
  final List<DriveInfo> drives;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Drives', style: text.titleMedium),
            const SizedBox(height: 12),
            for (final d in drives) ...[
              Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      d.kind == DriveKind.removable ? '${d.root} (USB)' : d.root,
                    ),
                  ),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: d.totalBytes == 0 ? 0 : d.usedBytes / d.totalBytes,
                      minHeight: 10,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 200,
                    child: Text(
                      '${formatBytes(d.freeBytes)} free of '
                      '${formatBytes(d.totalBytes)}',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScanCard extends StatelessWidget {
  const _ScanCard({required this.controller, required this.run});
  final AppController controller;
  final ScanRun? run;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final text = Theme.of(context).textTheme;
    final p = c.progress;
    final String status;
    if (c.scanning) {
      status = p == null
          ? 'Starting…'
          : 'Scanned ${plural(p.files, 'file')} (${formatBytes(p.bytes)}) — '
              '${p.currentDir}';
    } else if (c.scanError != null) {
      status = 'The scan stopped with an error: ${c.scanError}';
    } else if (run == null) {
      status = 'Scan your folders to see what can be cleaned up. '
          'Scanning only reads file names, sizes and dates.';
    } else {
      final when = run!.endedAt ?? run!.startedAt;
      final incomplete = run!.status != RunStatus.complete
          ? ' (incomplete — run the scan again to finish)'
          : '';
      status = 'Last scan ${formatDate(when)}: '
          '${plural(run!.files, 'file')}$incomplete'
          '${run!.unreadableDirs > 0 ? ' · ${plural(run!.unreadableDirs, 'folder')} could not be read' : ''}';
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Scan', style: text.titleMedium)),
                if (c.scanning)
                  OutlinedButton(
                    onPressed: c.cancelScan,
                    child: const Text('Stop'),
                  )
                else
                  FilledButton.icon(
                    onPressed: c.scan,
                    icon: const Icon(Icons.search),
                    label: Text(run == null ? 'Scan now' : 'Scan again'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (c.scanning) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
            ],
            Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(
              'Scanning: ${c.scanRoots.join(', ')}',
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 300,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 8),
                Text(label, style: text.bodyMedium),
                const SizedBox(height: 4),
                Text(value, style: text.headlineSmall),
                Text(detail, style: text.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PurgeBanner extends StatelessWidget {
  const _PurgeBanner({required this.summary, required this.onReview});
  final PurgeSummary summary;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: MaterialBanner(
        leading: const Icon(Icons.schedule),
        content: Text(
          '${plural(summary.count, 'file')} (${formatBytes(summary.bytes)}) '
          'have been in the trash for 30 days and are ready to be deleted '
          'permanently. Nothing is deleted until you confirm.',
        ),
        actions: [
          TextButton(onPressed: onReview, child: const Text('Review')),
        ],
      ),
    );
  }
}
