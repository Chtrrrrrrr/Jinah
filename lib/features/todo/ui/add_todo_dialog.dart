import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/todo_repository.dart';

/// Obsidian 任务列表式添加框。
Future<void> showAddTodoDialog(BuildContext context) {
  return showDialog(
    context: context,
    builder: (context) => const AddTodoDialog(),
  );
}

class AddTodoDialog extends ConsumerStatefulWidget {
  const AddTodoDialog({super.key});

  @override
  ConsumerState<AddTodoDialog> createState() => _AddTodoDialogState();
}

class _AddTodoDialogState extends ConsumerState<AddTodoDialog> {
  final _title = TextEditingController();
  DateTime? _dueDate;
  TimeOfDay? _dueTime;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (date != null) setState(() => _dueDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null) setState(() => _dueTime = time);
  }

  DateTime? get _dueAt {
    final d = _dueDate;
    if (d == null) return null;
    final t = _dueTime ?? const TimeOfDay(hour: 23, minute: 59);
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  void _save() {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    ref.read(todoRepositoryProvider).add(title: title, dueAt: _dueAt);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加 TODO'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(hintText: '要做什么？'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_dueDate == null
                    ? '截止日期'
                    : '${_dueDate!.month}/${_dueDate!.day}'),
              ),
              if (_dueDate != null)
                TextButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 16),
                  label: Text(_dueTime?.format(context) ?? '23:59'),
                ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('添加')),
      ],
    );
  }
}
