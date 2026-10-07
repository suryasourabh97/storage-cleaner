import 'package:flutter/material.dart';

import 'services/app_controller.dart';
import 'ui/files_page.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/trash_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppController? controller;
  Object? startupError;
  try {
    controller = AppController.open();
  } catch (e) {
    startupError = e;
  }
  runApp(StorageCleanerApp(controller: controller, startupError: startupError));
}

class StorageCleanerApp extends StatelessWidget {
  const StorageCleanerApp({super.key, this.controller, this.startupError});

  final AppController? controller;
  final Object? startupError;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return MaterialApp(
      title: 'Storage Cleaner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF00796B),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF00796B),
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      home: c == null
          ? Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Storage Cleaner could not start:\n\n$startupError',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            )
          : AppShell(controller: c),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  void _go(int i) => setState(() => _index = i);

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final pages = [
      HomePage(
        controller: c,
        onOpenOld: () => _go(1),
        onOpenLarge: () => _go(2),
        onOpenTrash: () => _go(3),
      ),
      FilesPage(key: const ValueKey('old'), controller: c, kind: FilesKind.old),
      FilesPage(
        key: const ValueKey('large'),
        controller: c,
        kind: FilesKind.large,
      ),
      TrashPage(controller: c),
      SettingsPage(controller: c),
    ];
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _go,
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: Text('Home'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history),
                label: Text('Old files'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.sd_storage_outlined),
                selectedIcon: Icon(Icons.sd_storage),
                label: Text('Large files'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.delete_outline),
                selectedIcon: Icon(Icons.delete),
                label: Text('Trash'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }
}
