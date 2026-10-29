import 'package:dio/dio.dart';

import 'canvas_models.dart';

/// Canvas REST API 客户端（用户自备 token，客户端直连，SPEC §4.2）。
class CanvasApi {
  CanvasApi(this._dio, this._token);

  final Dio _dio;
  final String _token;

  static const baseUrl = 'https://canvas.tongji.edu.cn';

  /// 每门课最多翻页数（保险丝，正常一学期远到不了）。
  static const maxPagesPerCourse = 5;

  Options get _auth => Options(
        headers: {'Authorization': 'Bearer $_token'},
        validateStatus: (code) => code != null && code < 500,
      );

  Future<List<CanvasCourse>> fetchCourses() async {
    final res = await _dio.get<List<dynamic>>(
      '/api/v1/courses',
      queryParameters: {'enrollment_state': 'active', 'per_page': 100},
      options: _auth,
    );
    _throwIfBad(res, '获取课程列表');
    return (res.data ?? [])
        .map((e) => CanvasCourse.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<CanvasAssignment>> fetchAssignments(int courseId) async {
    final out = <CanvasAssignment>[];
    String? nextPath = '/api/v1/courses/$courseId/assignments';
    final params = {'include[]': 'submission', 'per_page': 100, 'order_by': 'due_at'};

    var pages = 0;
    while (nextPath != null && pages < maxPagesPerCourse) {
      final res = await _dio.get<List<dynamic>>(
        nextPath,
        queryParameters: pages == 0 ? params : null,
        options: _auth,
      );
      _throwIfBad(res, '获取作业列表');
      for (final e in res.data ?? []) {
        out.add(CanvasAssignment.fromJson(e as Map<String, dynamic>));
      }
      nextPath = parseNextUrl(res.headers.value('link'));
      pages++;
    }
    return out;
  }

  void _throwIfBad(Response<dynamic> res, String what) {
    if (res.statusCode == 401) {
      throw CanvasAuthException('Canvas Token 无效或已过期，请在设置中重新填写');
    }
    if (res.statusCode != 200) {
      throw CanvasApiException('$what失败：HTTP ${res.statusCode}');
    }
  }
}

class CanvasApiException implements Exception {
  CanvasApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CanvasAuthException extends CanvasApiException {
  CanvasAuthException(super.message);
}
