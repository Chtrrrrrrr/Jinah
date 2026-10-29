import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'command_palette.dart';

/// Obsidian 式布局：桌面/平板左侧边栏（NavigationRail），窄屏变抽屉。
/// 全局 `Ctrl/Cmd + K` 唤起命令面板。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  void _openPalette() => showCommandPalette(context);

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;

    final body = Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _OpenPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _OpenPaletteIntent(),
      },
      child: Actions(
        actions: {
          _OpenPaletteIntent: CallbackAction<_OpenPaletteIntent>(
            onInvoke: (_) {
              _openPalette();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 840;
              if (wide) {
                return Row(
                  children: [
                    NavigationRail(
                      selectedIndex: shell.currentIndex,
                      onDestinationSelected: _onSelect,
                      labelType: NavigationRailLabelType.all,
                      leading: const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Jinah',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.calendar_view_week_outlined),
                          selectedIcon: Icon(Icons.calendar_view_week),
                          label: Text('课表'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.checklist_outlined),
                          selectedIcon: Icon(Icons.checklist),
                          label: Text('TODO'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.inbox_outlined),
                          selectedIcon: Icon(Icons.inbox),
                          label: Text('收件箱'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: Text('设置'),
                        ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: shell),
                  ],
                );
              }
              return Scaffold(
                body: shell,
                drawer: Drawer(
                  child: ListView(
                    children: [
                      const DrawerHeader(
                        child: Text(
                          'Jinah',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      for (final (i, item) in _destinations.indexed)
                        ListTile(
                          leading: Icon(item.$1),
                          title: Text(item.$2),
                          selected: shell.currentIndex == i,
                          onTap: () {
                            Navigator.of(context).pop();
                            _onSelect(i);
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    return body;
  }

  void _onSelect(int index) => widget.shell.goBranch(
        index,
        initialLocation: index == widget.shell.currentIndex,
      );
}

const _destinations = [
  (Icons.calendar_view_week_outlined, '课表'),
  (Icons.checklist_outlined, 'TODO'),
  (Icons.inbox_outlined, '收件箱'),
  (Icons.settings_outlined, '设置'),
];

class _OpenPaletteIntent extends Intent {
  const _OpenPaletteIntent();
}
