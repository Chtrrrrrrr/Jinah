import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../features/todo/data/todo_repository.dart';

sealed class BackupResult {
  const BackupResult();

  String describe() => switch (this) {
        BackupCancelled() => '已取消',
        BackupFailure(:final message) => '失败：$message',
        BackupExportOk(:final path) => '已导出到 $path',
        BackupImportOk(:final counts) =>
          '导入完成：${counts.entries.map((e) => '${e.key} ${e.value}').join('，')}',
      };
}

class BackupCancelled extends BackupResult {
  const BackupCancelled();
}

class BackupFailure extends BackupResult {
  const BackupFailure(this.message);

  final String message;
}

class BackupExportOk extends BackupResult {
  const BackupExportOk(this.path);

  final String path;
}

class BackupImportOk extends BackupResult {
  const BackupImportOk(this.counts);

  final Map<String, int> counts;
}

/// 全量备份：四个表序列化为一个 JSON 文件；导入时整库替换。
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const _version = 1;

  Future<BackupResult> exportToFile() async {
    final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
    final location = await getSaveLocation(
      suggestedName: 'jinah-backup-$stamp.json',
    );
    if (location == null) return const BackupCancelled();

    try {
      final todos = await _db.select(_db.todoItems).get();
      final courses = await _db.select(_db.courses).get();
      final terms = await _db.select(_db.terms).get();
      final entries = await _db.select(_db.scheduleEntries).get();

      final payload = {
        'app': 'jinah',
        'version': _version,
        'exportedAt': DateTime.now().toIso8601String(),
        'todoItems': todos.map((e) => e.toJson()).toList(),
        'courses': courses.map((e) => e.toJson()).toList(),
        'terms': terms.map((e) => e.toJson()).toList(),
        'scheduleEntries': entries.map((e) => e.toJson()).toList(),
      };

      final file = File(location.path);
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      return BackupExportOk(location.path);
    } catch (e) {
      return BackupFailure(e.toString());
    }
  }

  Future<BackupResult> importFromFile() async {
    final picked = await openFile(acceptedTypeGroups: [
      const XTypeGroup(
        label: 'JSON',
        extensions: ['json'],
        mimeTypes: ['application/json'],
      ),
    ]);
    if (picked == null) return const BackupCancelled();

    try {
      final text = await picked.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic> ||
          decoded['app'] != 'jinah' ||
          decoded['version'] != _version) {
        return const BackupFailure('不是有效的 Jinah 备份文件');
      }

      final todos = (decoded['todoItems'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(TodoItem.fromJson)
          .toList();
      final courses = (decoded['courses'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Course.fromJson)
          .toList();
      final terms = (decoded['terms'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(Term.fromJson)
          .toList();
      final entries = (decoded['scheduleEntries'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(ScheduleEntry.fromJson)
          .toList();

      await _db.transaction(() async {
        await _db.delete(_db.todoItems).go();
        await _db.delete(_db.scheduleEntries).go();
        await _db.delete(_db.courses).go();
        await _db.delete(_db.terms).go();

        await _db.batch((b) {
          b.insertAll(_db.terms, terms, mode: InsertMode.insertOrReplace);
          b.insertAll(_db.courses, courses, mode: InsertMode.insertOrReplace);
          b.insertAll(
            _db.scheduleEntries,
            entries,
            mode: InsertMode.insertOrReplace,
          );
          b.insertAll(_db.todoItems, todos, mode: InsertMode.insertOrReplace);
        });
      });

      return BackupImportOk({
        '课程': courses.length,
        '课表条目': entries.length,
        '学期': terms.length,
        '待办': todos.length,
      });
    } catch (e) {
      return BackupFailure(e.toString());
    }
  }
}

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(ref.watch(databaseProvider)),
);
