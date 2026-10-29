import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/core/ai/task_parser.dart';

void main() {
  group('extractJsonObject', () {
    test('从纯 JSON 中提取', () {
      expect(extractJsonObject('{"tasks": []}'), '{"tasks": []}');
    });

    test('容忍 markdown 代码围栏和前后说明', () {
      const out = '好的，解析结果如下：\n```json\n{"tasks": [{"title": "x"}]}\n```\n完。';
      expect(extractJsonObject(out), '{"tasks": [{"title": "x"}]}');
    });

    test('没有 JSON 时返回 null', () {
      expect(extractJsonObject('抱歉，我无法处理'), isNull);
    });
  });

  group('parseTasks', () {
    test('解析合法任务列表', () {
      const out = '''
      {
        "tasks": [
          {
            "course": "大学物理",
            "title": "完成第三章习题 1-10",
            "due": "2026-11-06T23:59:00+08:00",
            "submit_method": "Canvas 提交",
            "confidence": 0.92
          },
          { "title": "课前预习第四章", "due": null, "confidence": 0.4 }
        ]
      }
      ''';
      final tasks = parseTasks(out);
      expect(tasks.length, 2);
      expect(tasks[0].course, '大学物理');
      expect(tasks[0].due, DateTime.parse('2026-11-06T23:59:00+08:00'));
      expect(tasks[0].submitMethod, 'Canvas 提交');
      expect(tasks[0].confidence, 0.92);
      expect(tasks[1].due, isNull);
    });

    test('跳过无标题的无效条目，保留有效条目', () {
      const out = '{"tasks": [{"title": ""}, {"course": "高数"}, {"title": "valid"}]}';
      final tasks = parseTasks(out);
      expect(tasks.length, 1);
      expect(tasks.single.title, 'valid');
    });

    test('置信度钳制到 0-1', () {
      const out =
          '{"tasks": [{"title": "a", "confidence": 1.7}, {"title": "b", "confidence": -0.2}]}';
      final tasks = parseTasks(out);
      expect(tasks[0].confidence, 1.0);
      expect(tasks[1].confidence, 0.0);
    });

    test('非 JSON 输入抛异常', () {
      expect(() => parseTasks('没有 JSON'), throwsA(isA<TaskParseException>()));
    });

    test('缺少 tasks 数组抛异常', () {
      expect(
        () => parseTasks('{"result": "ok"}'),
        throwsA(isA<TaskParseException>()),
      );
    });
  });

  group('buildUserPrompt', () {
    test('注入格式化的当前时间', () {
      final p = buildUserPrompt(
        rawText: '周五前交作业',
        now: DateTime(2026, 10, 29, 8, 5),
      );
      expect(p, contains('当前时间：2026-10-29 08:05'));
      expect(p, contains('周五前交作业'));
    });
  });

  test('系统提示包含 Jinah 人格', () {
    expect(buildSystemPrompt(), contains('Jinah'));
  });
}
