import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/ai/task_parser.dart';
import '../../todo/data/todo_repository.dart';
import '../data/ai_parse_service.dart';

/// 解析收件箱：粘贴通知 → AI 提取 → 人工确认 → 入 TODO（SPEC §4.3 确认流）。
class InboxPage extends ConsumerStatefulWidget {
  const InboxPage({super.key});

  @override
  ConsumerState<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends ConsumerState<InboxPage> {
  final _input = TextEditingController();
  bool _parsing = false;
  bool _lastFromImage = false;
  List<ParsedTask>? _tasks;
  final Set<int> _selected = {};

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _parse() async {
    final text = _input.text.trim();
    if (text.isEmpty || _parsing) return;
    await _run(() => ref.read(aiParseServiceProvider).parse(text),
        fromImage: false);
  }

  /// 选择截图并走多模态解析。
  Future<void> _pickImage() async {
    if (_parsing) return;
    final picked = await openFile(acceptedTypeGroups: [
      XTypeGroup(
        label: '图片',
        extensions: ['png', 'jpg', 'jpeg', 'webp'],
        mimeTypes: ['image/*'],
      ),
    ]);
    if (picked == null || !mounted) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    await _run(
      () => ref
          .read(aiParseServiceProvider)
          .parseImage(bytes, mimeType: picked.mimeType ?? 'image/png'),
      fromImage: true,
    );
  }

  Future<void> _run(
    Future<AiParseResult> Function() task, {
    required bool fromImage,
  }) async {
    setState(() {
      _parsing = true;
      _tasks = null;
      _selected.clear();
    });

    final result = await task();

    if (!mounted) return;
    setState(() {
      _parsing = false;
      _lastFromImage = fromImage;
    });

    switch (result) {
      case AiNeedsKey():
        _toast('未配置 LLM API Key（设置 → 凭据）');
      case AiParseFailure(:final message):
        _toast(message);
      case AiParseOk(:final tasks):
        if (tasks.isEmpty) {
          _toast('没有从内容中提取到任务');
        } else {
          setState(() {
            _tasks = tasks;
            _selected.addAll(List.generate(tasks.length, (i) => i));
          });
        }
    }
  }

  Future<void> _commit() async {
    final tasks = _tasks;
    if (tasks == null) return;
    final repo = ref.read(todoRepositoryProvider);
    final dateFmt = DateFormat('MM-dd HH:mm');
    var added = 0;
    for (final i in _selected.toList()..sort()) {
      final t = tasks[i];
      await repo.add(
        title: t.title,
        dueAt: t.due,
        detail: [
          if (t.course != null) t.course,
          if (t.submitMethod != null) t.submitMethod,
          if (t.due != null) '截止 ${dateFmt.format(t.due!.toLocal())}',
        ].join(' · '),
        source: _lastFromImage ? 'screenshot' : 'manual',
      );
      added++;
    }
    setState(() {
      _tasks = null;
      _selected.clear();
      _input.clear();
    });
    _toast('已添加 $added 条待办');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('解析收件箱', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '把微信群/QQ群/邮件里的作业通知粘贴到这里，Jinah 会提取课程、内容、截止时间',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _input,
            maxLines: _tasks == null ? 8 : 4,
            decoration: const InputDecoration(
              hintText: '粘贴作业通知原文…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 12),
          if (_tasks == null)
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _parsing ? null : _parse,
                  icon: _parsing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_parsing ? '解析中…' : 'AI 解析'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: _parsing ? null : _pickImage,
                  icon: const Icon(Icons.screenshot, size: 16),
                  label: const Text('导入截图'),
                ),
              ],
            ),
          if (_tasks != null) ...[
            Row(
              children: [
                Text(
                  '提取到 ${_tasks!.length} 条任务，勾选后确认：',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(
                    () => _selected.addAll(
                      List.generate(_tasks!.length, (i) => i),
                    ),
                  ),
                  child: const Text('全选'),
                ),
                TextButton(
                  onPressed: () => setState(_selected.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
            for (final (i, t) in _tasks!.indexed)
              _TaskConfirmTile(
                index: i,
                task: t,
                selected: _selected.contains(i),
                accent: accent,
                onChanged: (v) => setState(
                  () => v ? _selected.add(i) : _selected.remove(i),
                ),
                onRemove: () {
                  // 先剔除被删下标，再把其后所有下标前移一位
                  final next = _selected
                      .where((x) => x != i)
                      .map((x) => x > i ? x - 1 : x)
                      .toSet();
                  setState(() {
                    _tasks!.removeAt(i);
                    _selected
                      ..clear()
                      ..addAll(next);
                  });
                },
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _selected.isEmpty ? null : _commit,
                  icon: const Icon(Icons.add_task, size: 16),
                  label: Text('加入 TODO（${_selected.length}）'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _tasks = null;
                    _selected.clear();
                  }),
                  child: const Text('放弃'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TaskConfirmTile extends StatelessWidget {
  const _TaskConfirmTile({
    required this.index,
    required this.task,
    required this.selected,
    required this.accent,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final ParsedTask task;
  final bool selected;
  final Color accent;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    final dateFmt = DateFormat('MM-dd HH:mm');
    final lowConfidence = task.confidence < 0.7;

    return CheckboxListTile(
      value: selected,
      onChanged: (v) => onChanged(v ?? false),
      activeColor: accent,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        task.title,
        style: TextStyle(
          decoration: selected ? null : TextDecoration.lineThrough,
          color: selected ? null : muted,
        ),
      ),
      subtitle: Text(
        [
          if (task.course != null) task.course,
          if (task.due != null) '截止 ${dateFmt.format(task.due!.toLocal())}',
          if (task.submitMethod != null) task.submitMethod,
          if (lowConfidence) '⚠ 置信度 ${(task.confidence * 100).round()}%',
        ].join(' · '),
        style: TextStyle(
          fontSize: 12,
          color: lowConfidence ? Colors.amber.shade700 : muted,
        ),
      ),
      secondary: IconButton(
        tooltip: '移除',
        icon: Icon(Icons.close, size: 16, color: muted),
        onPressed: onRemove,
      ),
    );
  }
}
