import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/canvas/data/canvas_sync.dart';
import '../features/todo/ui/add_todo_dialog.dart';

class _PaletteAction {
  const _PaletteAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.run,
    this.syncCanvas = false,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final void Function(BuildContext context) run;

  /// 特殊动作：需要 WidgetRef，不走 [run]。
  final bool syncCanvas;
}

List<_PaletteAction> _actions(BuildContext context) => [
      _PaletteAction(
        title: '跳转到 TODO',
        subtitle: '作业与任务清单',
        icon: Icons.checklist,
        run: (c) => c.go('/todo'),
      ),
      _PaletteAction(
        title: '跳转到课表',
        subtitle: '本周课程',
        icon: Icons.calendar_view_week,
        run: (c) => c.go('/timetable'),
      ),
      _PaletteAction(
        title: '跳转到收件箱',
        subtitle: '粘贴/分享通知，AI 解析',
        icon: Icons.inbox,
        run: (c) => c.go('/inbox'),
      ),
      _PaletteAction(
        title: '跳转到设置',
        subtitle: '外观与凭据',
        icon: Icons.settings,
        run: (c) => c.go('/settings'),
      ),
      _PaletteAction(
        title: '添加 TODO',
        subtitle: '手动添加任务',
        icon: Icons.add_task,
        run: (c) => showAddTodoDialog(c),
      ),
      _PaletteAction(
        title: '同步 Canvas 作业',
        subtitle: '拉取所有课程的作业到 TODO',
        icon: Icons.cloud_sync,
        run: (_) {},
        syncCanvas: true,
      ),
    ];

/// Obsidian 式命令面板（Ctrl/Cmd+K）。
Future<void> showCommandPalette(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const _CommandPaletteDialog(),
  );
}

class _CommandPaletteDialog extends ConsumerStatefulWidget {
  const _CommandPaletteDialog();

  @override
  ConsumerState<_CommandPaletteDialog> createState() =>
      _CommandPaletteDialogState();
}

class _CommandPaletteDialogState
    extends ConsumerState<_CommandPaletteDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final actions = _actions(context)
        .where(
          (a) =>
              _query.isEmpty ||
              a.title.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 96, left: 24, right: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '输入命令或搜索…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: actions.length,
                itemBuilder: (context, i) {
                  final a = actions[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(a.icon, size: 20),
                    title: Text(a.title),
                    subtitle: Text(
                      a.subtitle,
                      style: const TextStyle(fontSize: 12),
                    ),
                    onTap: () async {
                      Navigator.of(context).pop();
                      if (a.syncCanvas) {
                        await runCanvasSyncWithFeedback(context, ref);
                      } else {
                        a.run(context);
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
