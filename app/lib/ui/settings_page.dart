import 'package:cleaner_core/cleaner_core.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../platform/windows/system_info.dart';
import '../services/app_controller.dart';
import 'format.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.controller});
  final AppController controller;

  Future<void> _addExclusion(BuildContext context) async {
    final dir = await getDirectoryPath(confirmButtonText: 'Never touch');
    if (dir != null) controller.addExclusion(dir);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final text = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: const Text('Settings')),
          body: ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                title: const Text('Old files: not modified for'),
                trailing: DropdownButton<AgeThreshold>(
                  value: c.settings.age,
                  items: [
                    for (final a in AgeThreshold.values)
                      DropdownMenuItem(value: a, child: Text(ageLabel(a))),
                  ],
                  onChanged: (a) {
                    if (a != null) c.setAge(a);
                  },
                ),
              ),
              ListTile(
                title: const Text('Large files: at least'),
                trailing: DropdownButton<SizeThreshold>(
                  value: c.settings.size,
                  items: [
                    for (final s in SizeThreshold.values)
                      DropdownMenuItem(value: s, child: Text(sizeLabel(s))),
                  ],
                  onChanged: (s) {
                    if (s != null) c.setSize(s);
                  },
                ),
              ),
              SwitchListTile(
                title: const Text('Scan USB and other removable drives'),
                value: c.settings.scanRemovableDrives,
                onChanged: c.setScanRemovable,
              ),
              const Divider(),
              ListTile(
                title: Text('Never touch these folders', style: text.titleMedium),
                subtitle: const Text(
                  'Excluded folders are not scanned and their files are never offered.',
                ),
                trailing: OutlinedButton.icon(
                  onPressed: () => _addExclusion(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add folder'),
                ),
              ),
              for (final e in c.exclusions)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(e),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => c.removeExclusion(e),
                  ),
                ),
              const Divider(),
              ListTile(
                title: Text('Scanned locations', style: text.titleMedium),
                subtitle: Text(c.scanRoots.join('\n')),
              ),
              ListTile(
                title: Text('Trash folders', style: text.titleMedium),
                subtitle: const Text(
                  'Each drive keeps its own StorageCleaner Trash folder with a '
                  'README and a list of where every file came from. Uninstalling '
                  'the app does not delete them.',
                ),
              ),
              for (final root in c.trashRoots)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(root),
                  trailing: TextButton(
                    onPressed: () => openInExplorer(root),
                    child: const Text('Open'),
                  ),
                ),
              const Divider(),
              ListTile(
                title: Text('Protected locations', style: text.titleMedium),
                subtitle: Text(
                  'Never scanned or changed:\n${c.protectedRoots.join('\n')}',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
