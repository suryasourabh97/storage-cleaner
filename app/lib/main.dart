import 'package:cleaner_core/cleaner_core.dart';
import 'package:flutter/gestures.dart' show kBackMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/app_controller.dart';
import 'ui/duplicates_page.dart';
import 'ui/files_page.dart';
import 'ui/format.dart';
import 'ui/home_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';
import 'ui/trash_page.dart';
import 'ui/widgets/components.dart';

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
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      home: c == null
          ? Scaffold(
              body: EmptyStartup(error: '$startupError'),
            )
          : AppShell(controller: c),
    );
  }
}

class EmptyStartup extends StatelessWidget {
  const EmptyStartup({super.key, required this.error});
  final String error;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Storage Cleaner could not open its data folder.\n\n$error',
            textAlign: TextAlign.center,
          ),
        ),
      );
}

enum _Section { home, old, large, duplicates, trash, settings }

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});
  final AppController controller;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  _Section _section = _Section.home;

  /// Screens visited before the current one, most recent last.
  final List<_Section> _history = [];

  void _go(_Section s) {
    if (s == _section) return;
    setState(() {
      _history.add(_section);
      if (_history.length > 50) _history.removeAt(0);
      _section = s;
    });
  }

  void _back() {
    if (_history.isEmpty) return;
    setState(() => _section = _history.removeLast());
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final page = switch (_section) {
      _Section.home => HomePage(
          controller: c,
          onOpenOld: () => _go(_Section.old),
          onOpenLarge: () => _go(_Section.large),
          onOpenDuplicates: () => _go(_Section.duplicates),
          onOpenTrash: () => _go(_Section.trash),
        ),
      _Section.old => FilesPage(
          key: const ValueKey('old'),
          controller: c,
          kind: FilesKind.old,
        ),
      _Section.large => FilesPage(
          key: const ValueKey('large'),
          controller: c,
          kind: FilesKind.large,
        ),
      _Section.duplicates => DuplicatesPage(controller: c),
      _Section.trash => TrashPage(controller: c),
      _Section.settings => SettingsPage(controller: c),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): _back,
        const SingleActivator(LogicalKeyboardKey.browserBack): _back,
      },
      child: Focus(
        autofocus: true,
        child: Listener(
          // The "back" side button on a mouse.
          onPointerDown: (e) {
            if (e.buttons & kBackMouseButton != 0) _back();
          },
          child: Scaffold(
            body: Row(
              children: [
                _Sidebar(controller: c, current: _section, onSelect: _go),
                Expanded(
                  child: BackNavigation(
                    onBack: _history.isEmpty ? null : _back,
                    child: page,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.controller,
    required this.current,
    required this.onSelect,
  });

  final AppController controller;
  final _Section current;
  final ValueChanged<_Section> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final text = Theme.of(context).textTheme;
    const items = [
      (_Section.home, Icons.space_dashboard_outlined, 'Overview'),
      (_Section.old, Icons.history, 'Old files'),
      (_Section.large, Icons.straighten, 'Large files'),
      (_Section.duplicates, Icons.difference_outlined, 'Duplicates'),
      (_Section.trash, Icons.delete_outline, 'Trash'),
      (_Section.settings, Icons.tune, 'Settings'),
    ];
    return Container(
      width: 228,
      color: t.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 16, 24),
              child: Text('Storage Cleaner', style: text.headlineSmall),
            ),
            for (final (section, icon, label) in items)
              _NavItem(
                icon: icon,
                label: label,
                selected: current == section,
                onTap: () => onSelect(section),
              ),
            const Spacer(),
            ListenableBuilder(
              listenable: controller,
              builder: (context, _) => _SidebarFooter(controller: controller),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.only(left: 21, right: 16),
          decoration: BoxDecoration(
            color: selected ? t.paper : null,
            border: Border(
              left: BorderSide(
                color: selected ? t.amber : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: selected ? t.ink : t.muted),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? t.ink : t.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows background work wherever the user is.
class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final t = context.tokens;
    final style = TextStyle(color: t.muted, fontSize: 12);
    String? line;
    if (c.scanning) {
      final p = c.progress;
      line = p == null ? 'Scanning' : 'Scanning, ${plural(p.files, 'file')}';
    } else if (c.analyzing) {
      line = 'Looking for duplicates';
    }
    final run = c.latestRun;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (line != null) ...[
            const LinearProgressIndicator(minHeight: 2),
            const SizedBox(height: 6),
            Text(line, style: style),
          ] else if (run != null)
            Text(
              run.status == RunStatus.complete
                  ? 'Scanned ${formatDate(run.endedAt ?? run.startedAt)}'
                  : 'Last scan incomplete',
              style: style,
            ),
        ],
      ),
    );
  }
}
