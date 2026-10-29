/// Canvas REST API 数据模型与纯解析逻辑（无网络依赖，可单测）。
library;

class CanvasCourse {
  CanvasCourse({
    required this.id,
    required this.name,
    this.courseCode,
  });

  factory CanvasCourse.fromJson(Map<String, dynamic> json) => CanvasCourse(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        courseCode: json['course_code'] as String?,
      );

  final int id;
  final String name;
  final String? courseCode;
}

class CanvasSubmission {
  CanvasSubmission({this.workflowState});

  factory CanvasSubmission.fromJson(Map<String, dynamic> json) =>
      CanvasSubmission(
        workflowState: json['workflow_state'] as String?,
      );

  final String? workflowState;
}

class CanvasAssignment {
  CanvasAssignment({
    required this.id,
    required this.courseId,
    required this.name,
    this.dueAt,
    this.htmlUrl,
    this.pointsPossible,
    this.submission,
  });

  factory CanvasAssignment.fromJson(Map<String, dynamic> json) =>
      CanvasAssignment(
        id: (json['id'] as num).toInt(),
        courseId: (json['course_id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        dueAt: json['due_at'] == null
            ? null
            : DateTime.tryParse(json['due_at'] as String),
        htmlUrl: json['html_url'] as String?,
        pointsPossible: (json['points_possible'] as num?)?.toDouble(),
        submission: json['submission'] == null
            ? null
            : CanvasSubmission.fromJson(
                json['submission'] as Map<String, dynamic>,
              ),
      );

  final int id;
  final int courseId;
  final String name;
  final DateTime? dueAt;
  final String? htmlUrl;
  final double? pointsPossible;
  final CanvasSubmission? submission;
}

/// 是否值得导入 TODO：已交/已评分的跳过，无截止时间的跳过。
bool isActionable(CanvasAssignment a) {
  const doneStates = {'submitted', 'graded', 'complete', 'pending_review'};
  final ws = a.submission?.workflowState;
  if (ws != null && doneStates.contains(ws)) return false;
  return a.dueAt != null;
}

/// 从 Canvas 的 `Link` 响应头解析 rel="next" 分页地址（相对路径）。
String? parseNextUrl(String? linkHeader) {
  if (linkHeader == null || linkHeader.isEmpty) return null;
  for (final part in linkHeader.split(',')) {
    final segments = part.split(';');
    if (segments.length < 2) continue;
    final rel = segments
        .sublist(1)
        .map((s) => s.trim())
        .firstWhere(
          (s) => s.startsWith('rel="') && s.endsWith('"'),
          orElse: () => '',
        );
    if (rel == 'rel="next"') {
      final url = segments.first.trim();
      return url.substring(1, url.length - 1); // 去掉 <>
    }
  }
  return null;
}
