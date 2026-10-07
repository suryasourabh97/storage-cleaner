import 'package:cleaner_core/cleaner_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../platform/windows/system_info.dart';
import '../services/app_controller.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets/components.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  Future<void> _addExclusion() async {
    final dir = await getDirectoryPath(confirmButtonText: 'Never touch');
    if (dir != null) controller.addExclusion(dir);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        return ListView(
          children: [
            const PageHeader(title: 'Settings'),
            const Divider(),
            _Section(
              title: 'What counts as',
              children: [
                _SettingRow(
                  label: 'An old file',
                  hint: 'Judged by the date it was last changed.',
                  control: InlineDropdown<AgeThreshold>(
                    label: 'Not modified for',
                    value: c.settings.age,
                    values: AgeThreshold.values,
                    labelOf: ageLabel,
                    onChanged: c.setAge,
                  ),
                ),
                _SettingRow(
                  label: 'A large file',
                  control: InlineDropdown<SizeThreshold>(
                    label: 'At least',
                    value: c.settings.size,
                    values: SizeThreshold.values,
                    labelOf: sizeLabel,
                    onChanged: c.setSize,
                  ),
                ),
                _SettingRow(
                  label: 'Similar photos',
                  hint: 'Also find smaller or re-saved copies of the same '
                      'photo when checking for duplicates.',
                  control: Switch(
                    value: c.settings.similarPhotos,
                    onChanged: c.setSimilarPhotos,
                  ),
                ),
                _SettingRow(
                  label: 'A duplicate worth checking',
                  hint: 'Smaller files take long to compare and free little.',
                  control: InlineDropdown<DuplicateMinSize>(
                    label: 'At least',
                    value: c.settings.duplicateMin,
                    values: DuplicateMinSize.values,
                    labelOf: minSizeLabel,
                    onChanged: c.setDuplicateMin,
                  ),
                ),
              ],
            ),
            _Section(
              title: 'Where to look',
              children: [
                _SettingRow(
                  label: 'USB and other removable drives',
                  hint: 'Off by default.',
                  control: Switch(
                    value: c.settings.scanRemovableDrives,
                    onChanged: c.setScanRemovable,
                  ),
                ),
                _SettingRow(
                  label: 'Scanned',
                  hint: c.scanRoots.join('\n'),
                ),
                _SettingRow(
                  label: 'Never touch these folders',
                  hint: c.exclusions.isEmpty
                      ? 'Folders you add here are not scanned, and nothing in '
                          'them is offered for removal.'
                      : null,
                  control: OutlinedButton.icon(
                    onPressed: _addExclusion,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add folder'),
                  ),
                ),
                for (final e in c.exclusions)
                  _PathRow(
                    path: e,
                    action: TextButton(
                      onPressed: () => c.removeExclusion(e),
                      child: const Text('Remove'),
                    ),
                  ),
              ],
            ),
            _Section(
              title: 'Trash folders',
              children: [
                const _SettingRow(
                  label: 'One per drive',
                  hint: 'Each holds a README and a list of where every file '
                      'came from. Uninstalling the app leaves them in place.',
                ),
                for (final root in c.trashRoots)
                  _PathRow(
                    path: root,
                    action: TextButton(
                      onPressed: () => openInExplorer(root),
                      child: const Text('Open'),
                    ),
                  ),
              ],
            ),
            _Section(
              title: 'Never scanned or changed',
              children: [
                _SettingRow(
                  label: 'Windows and app folders',
                  hint: c.protectedRoots.join('\n'),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, this.hint, this.control});
  final String label;
  final String? hint;
  final Widget? control;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: context.tokens.line)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodyLarge),
                if (hint != null) ...[
                  const SizedBox(height: 2),
                  Text(hint!, style: text.bodySmall),
                ],
              ],
            ),
          ),
          if (control != null) ...[const SizedBox(width: 16), control!],
        ],
      ),
    );
  }
}

class _PathRow extends StatelessWidget {
  const _PathRow({required this.path, required this.action});
  final String path;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              path,
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          action,
        ],
      ),
    );
  }
}
