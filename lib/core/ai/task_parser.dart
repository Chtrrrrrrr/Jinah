/// AI 作业解析的 Prompt 组装与结果校验（纯函数，无网络依赖，可单测）。
library;

import 'dart:convert';

class ParsedTask {
  const ParsedTask({
    required this.title,
    this.course,
    this.due,
    this.submitMethod,
    this.confidence = 0.5,
  });

  final String title;
  final String? course;
  final DateTime? due;
  final String? submitMethod;

  /// 0.0 - 1.0
  final double confidence;
}

/// 从通知文本提取作业任务的系统提示（SPEC §4.3）。
String buildSystemPrompt() => '''
你是 Jinah，同济大学学生的 AI 学习助手。你的职责之一是从老师发布的通知文本中提取作业/任务条目。

输出严格的 JSON（不要输出其他任何内容）：
{
  "tasks": [
    {
      "course": "课程名（尽量从上下文推断；推断不出用 null）",
      "title": "任务标题（简短动宾短语）",
      "due": "截止时间，ISO8601 带时区（如 2026-11-06T23:59:00+08:00）；通知没写截止则用 null",
      "submit_method": "提交方式（如 Canvas 提交/课上交/发邮箱；没写则用 null）",
      "confidence": 0.0到1.0之间的置信度
    }
  ]
}

规则：
- 一条通知可能包含多个任务，逐个提取；没有任务则输出 {"tasks": []}
- 相对时间（"本周五""下周三前"）按用户消息里给出的当前时间换算成绝对时间
- 不是作业的内容（打招呼、提醒、资料分享）不要提取
- title 用中文，保留必要的章节/编号信息
''';

/// 用户消息：注入当前时间（相对时间换算的依据）+ 原文。
String buildUserPrompt({required String rawText, required DateTime now}) {
  final local = now.toLocal();
  final stamp =
      '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
  return '当前时间：$stamp（UTC+8）\n\n通知内容：\n$rawText';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// 截图解析的用户消息。
String buildImageUserPrompt({required DateTime now}) {
  final local = now.toLocal();
  final stamp =
      '${local.year}-${_two(local.month)}-${_two(local.day)} ${_two(local.hour)}:${_two(local.minute)}';
  return '当前时间：$stamp（UTC+8）\n\n图片内容：老师发的作业通知截图，或一张课程表截图。'
      '请提取其中的作业任务（课程、标题、截止时间、提交方式）。纯课程表截图若没有作业信息，输出 {"tasks": []}。';
}

/// 从 LLM 输出中提取第一个 JSON 对象（容忍 markdown 代码围栏和前后废话）。
String? extractJsonObject(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  return text.substring(start, end + 1);
}

class TaskParseException implements Exception {
  const TaskParseException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 解析并校验 LLM 输出。无效条目跳过；完全不是任务 JSON 时抛异常。
List<ParsedTask> parseTasks(String llmOutput) {
  final jsonText = extractJsonObject(llmOutput);
  if (jsonText == null) {
    throw const TaskParseException('AI 输出中没有找到 JSON');
  }

  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic> ||
      decoded['tasks'] is! List<dynamic>) {
    throw const TaskParseException('AI 输出结构不符（缺少 tasks 数组）');
  }

  final out = <ParsedTask>[];
  for (final entry in decoded['tasks'] as List<dynamic>) {
    if (entry is! Map<String, dynamic>) continue;
    final title = entry['title'];
    if (title is! String || title.trim().isEmpty) continue;

    DateTime? due;
    final dueRaw = entry['due'];
    if (dueRaw is String && dueRaw.isNotEmpty) {
      due = DateTime.tryParse(dueRaw);
    }

    var confidence = 0.5;
    final confRaw = entry['confidence'];
    if (confRaw is num) {
      confidence = confRaw.toDouble().clamp(0.0, 1.0);
    }

    out.add(ParsedTask(
      title: title.trim(),
      course: entry['course'] is String && (entry['course'] as String).isNotEmpty
          ? (entry['course'] as String).trim()
          : null,
      due: due,
      submitMethod: entry['submit_method'] is String &&
              (entry['submit_method'] as String).isNotEmpty
          ? (entry['submit_method'] as String).trim()
          : null,
      confidence: confidence,
    ));
    if (out.length >= 20) break; // 保险丝：一次通知最多 20 条
  }
  return out;
}
