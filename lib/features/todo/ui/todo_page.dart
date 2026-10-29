import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/database/database.dart';
import '../../canvas/data/canvas_sync.dart';
import '../data/todo_repository.dart';
import 'add_todo_dialog.dart';

/// TODO 主页面：Obsidian 任务列表风格。
class TodoPage extends ConsumerWidget {
  const TodoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final todos = ref.watch(todoListProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        onPressed: () => showAddTodoDialog(context),
        tooltip: '添加 TODO',
        child: const Icon(Icons.add),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
            child: Row(
              children: [
                Text('TODO', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                IconButton(
                  tooltip: '同步 Canvas 作业',
                  icon: const Icon(Icons.cloud_sync_outlined),
                  onPressed: () => runCanvasSyncWithFeedback(context, ref),
                ),
              ],
            ),
          ),
          Expanded(
            child: todos.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('加载失败：$e')),
              data: (items) => items.isEmpty
                  ? const _EmptyState()
                  : _TodoList(items: items),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist, size: 48, color: muted),
          const SizedBox(height: 12),
          Text('没有待办任务', style: TextStyle(color: muted)),
          const SizedBox(height: 4),
          Text(
            '按 Ctrl+K 或右下角 + 添加，粘贴作业通知到收件箱',
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String _sectionOf(TodoItem item, DateTime now) {
  final due = item.dueAt;
  if (due == null) return '无截止日期';
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfDue = DateTime(due.year, due.month, due.day);
  final diff = startOfDue.difference(startOfToday).inDays;
  if (diff < 0) return '已过期';
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  if (diff < 7) return '本周';
  return '更晚';
}

const _sectionOrder = ['已过期', '今天', '明天', '本周', '更晚', '无截止日期'];

class _TodoList extends ConsumerWidget {
  const _TodoList({required this.items});

  final List<TodoItem> items;

  /// 仓库只在用户操作时读取（不在 build 期实例化数据库）。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final dateFmt = DateFormat('MM-dd HH:mm');

    final sections = <String, List<TodoItem>>{};
    for (final item in items) {
      sections.putIfAbsent(_sectionOf(item, DateTime.now()), () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        for (final name in _sectionOrder)
          if (sections[name] != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              child: Text(
                name,
                style: TextStyle(
                  color: muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            for (final item in sections[name]!)
              _TodoTile(
                item: item,
                muted: muted,
                dueLabel: item.dueAt == null
                    ? null
                    : dateFmt.format(item.dueAt!.toLocal()),
                onToggle: () =>
                    ref.read(todoRepositoryProvider).toggle(item),
                onDelete: () =>
                    ref.read(todoRepositoryProvider).delete(item),
              ),
          ],
      ],
    );
  }
}

class _TodoTile extends StatelessWidget {
  const _TodoTile({
    required this.item,
    required this.muted,
    required this.dueLabel,
    required this.onToggle,
    required this.onDelete,
  });

  final TodoItem item;
  final Color? muted;
  final String? dueLabel;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Row(
          children: [
            Checkbox(
              value: false,
              onChanged: (_) => onToggle(),
              activeColor: accent,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (item.detail != null && item.detail!.isNotEmpty)
                    Text(
                      item.detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                ],
              ),
            ),
            if (item.source != 'manual')
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _SourcePill(source: item.source),
              ),
            if (dueLabel != null)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(dueLabel!, style: TextStyle(fontSize: 12, color: muted)),
              ),
            IconButton(
              icon: Icon(Icons.close, size: 16, color: muted),
              tooltip: '删除',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _SourcePill extends StatelessWidget {
  const _SourcePill({required this.source});

  final String source;

  static const _labels = {
    'canvas': 'Canvas',
    'notice': '1系统',
    'screenshot': '截图',
  };

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _labels[source] ?? source,
        style: TextStyle(fontSize: 10, color: muted),
      ),
    );
  }
}
