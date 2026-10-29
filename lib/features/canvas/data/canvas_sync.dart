import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/secrets/secret_store.dart';
import '../../todo/data/course_repository.dart';
import '../../todo/data/todo_repository.dart';
import 'canvas_api.dart';
import 'canvas_models.dart';

sealed class CanvasSyncResult {
  const CanvasSyncResult();

  String describe() => switch (this) {
        CanvasNeedsToken() => '未配置 Canvas Token（设置 → 凭据）',
        CanvasSyncFailure(:final message) => '同步失败：$message',
        CanvasSyncOk(:final courses, :final added) =>
          '同步完成：$courses 门课，新增 $added 条待办',
      };
}

class CanvasNeedsToken extends CanvasSyncResult {
  const CanvasNeedsToken();
}

class CanvasSyncOk extends CanvasSyncResult {
  const CanvasSyncOk({required this.courses, required this.added});

  final int courses;
  final int added;
}

class CanvasSyncFailure extends CanvasSyncResult {
  const CanvasSyncFailure(this.message);

  final String message;
}

class CanvasSyncService {
  CanvasSyncService(this._secrets, this._todos, this._courses);

  final SecretStore _secrets;
  final TodoRepository _todos;
  final CourseRepository _courses;

  Future<CanvasSyncResult> sync() async {
    final token = await _secrets.canvasToken;
    if (token == null || token.isEmpty) {
      return const CanvasNeedsToken();
    }

    try {
      final dio = Dio(BaseOptions(
        baseUrl: CanvasApi.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      final api = CanvasApi(dio, token);

      final courses = await api.fetchCourses();
      var added = 0;
      for (final course in courses) {
        final local = await _courses.upsertFromSource(
          source: 'canvas',
          sourceRef: 'course_${course.id}',
          name: course.name,
        );
        final assignments = await api.fetchAssignments(course.id);
        for (final a in assignments) {
          if (!isActionable(a)) continue;
          final sourceRef = 'assignment_${a.id}';
          if (await _todos.findBySourceRef('canvas', sourceRef) != null) {
            continue;
          }
          await _todos.add(
            title: a.name,
            dueAt: a.dueAt,
            courseId: local.id,
            source: 'canvas',
            sourceRef: sourceRef,
            detail: course.name,
          );
          added++;
        }
      }
      return CanvasSyncOk(courses: courses.length, added: added);
    } on CanvasAuthException catch (e) {
      return CanvasSyncFailure(e.message);
    } on DioException catch (e) {
      return CanvasSyncFailure('网络错误：${e.message ?? e.type.name}');
    } on CanvasApiException catch (e) {
      return CanvasSyncFailure(e.message);
    }
  }
}

final canvasSyncServiceProvider = Provider<CanvasSyncService>(
  (ref) => CanvasSyncService(
    ref.watch(secretStoreProvider),
    ref.watch(todoRepositoryProvider),
    ref.watch(courseRepositoryProvider),
  ),
);

/// UI 入口：执行同步并用 SnackBar 反馈结果。
Future<void> runCanvasSyncWithFeedback(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('正在同步 Canvas 作业…')),
  );
  final result = await ref.read(canvasSyncServiceProvider).sync();
  if (!context.mounted) return;
  messenger.showSnackBar(SnackBar(content: Text(result.describe())));
}
