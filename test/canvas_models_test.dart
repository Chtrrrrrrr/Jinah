import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/features/canvas/data/canvas_models.dart';

void main() {
  group('CanvasAssignment.fromJson', () {
    test('解析含提交状态的作业', () {
      final a = CanvasAssignment.fromJson({
        'id': 101,
        'course_id': 7,
        'name': '第三章习题',
        'due_at': '2026-11-06T15:59:59Z',
        'html_url': 'https://canvas.tongji.edu.cn/courses/7/assignments/101',
        'points_possible': 10.0,
        'submission': {'workflow_state': 'unsubmitted'},
      });
      expect(a.id, 101);
      expect(a.courseId, 7);
      expect(a.name, '第三章习题');
      expect(a.dueAt, DateTime.parse('2026-11-06T15:59:59Z'));
      expect(a.dueAt!.isUtc, isTrue);
      expect(a.submission!.workflowState, 'unsubmitted');
    });

    test('无截止时间时 dueAt 为 null', () {
      final a = CanvasAssignment.fromJson({
        'id': 102,
        'course_id': 7,
        'name': '无截止作业',
        'due_at': null,
      });
      expect(a.dueAt, isNull);
      expect(a.submission, isNull);
    });
  });

  group('isActionable', () {
    CanvasAssignment build({
      String? workflowState,
      DateTime? dueAt,
    }) =>
        CanvasAssignment(
          id: 1,
          courseId: 1,
          name: 'x',
          dueAt: dueAt,
          submission:
              workflowState == null ? null : CanvasSubmission(workflowState: workflowState),
        );

    test('未提交 + 有截止 → 导入', () {
      expect(
        isActionable(build(workflowState: 'unsubmitted', dueAt: DateTime(2026))),
        isTrue,
      );
    });

    test('无提交记录 + 有截止 → 导入', () {
      expect(isActionable(build(dueAt: DateTime(2026))), isTrue);
    });

    test('已提交 → 跳过', () {
      expect(
        isActionable(build(workflowState: 'submitted', dueAt: DateTime(2026))),
        isFalse,
      );
    });

    test('已评分 → 跳过', () {
      expect(
        isActionable(build(workflowState: 'graded', dueAt: DateTime(2026))),
        isFalse,
      );
    });

    test('无截止时间 → 跳过（不制造噪音）', () {
      expect(isActionable(build(workflowState: 'unsubmitted')), isFalse);
    });
  });

  group('parseNextUrl', () {
    test('解析 rel=next', () {
      const header =
          '<https://canvas.tongji.edu.cn/api/v1/courses/7/assignments?page=2>; rel="next", '
          '<https://canvas.tongji.edu.cn/api/v1/courses/7/assignments?page=3>; rel="last"';
      expect(
        parseNextUrl(header),
        'https://canvas.tongji.edu.cn/api/v1/courses/7/assignments?page=2',
      );
    });

    test('只有 last 时返回 null（没有下一页）', () {
      const header =
          '<https://canvas.tongji.edu.cn/api/v1/courses/7/assignments?page=1>; rel="last"';
      expect(parseNextUrl(header), isNull);
    });

    test('空 header 返回 null', () {
      expect(parseNextUrl(null), isNull);
      expect(parseNextUrl(''), isNull);
    });
  });
}
