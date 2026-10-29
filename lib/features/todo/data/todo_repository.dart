import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';

/// open 条目按截止时间升序（无截止排最后），done/dismissed 不入此流。
Stream<List<TodoItem>> _watchOpen(AppDatabase db) {
  final query = db.select(db.todoItems)
    ..where((t) => t.status.equals('open'))
    ..orderBy([
      // NULL 截止日期排最后：先按 isNull 分组，再组内按时间升序
      (t) => OrderingTerm(expression: t.dueAt.isNull(), mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.dueAt, mode: OrderingMode.asc),
      (t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc),
    ]);
  return query.watch();
}

class TodoRepository {
  TodoRepository(this._db);

  final AppDatabase _db;

  Stream<List<TodoItem>> watchOpen() => _watchOpen(_db);

  Future<void> add({
    required String title,
    DateTime? dueAt,
    String? courseId,
    String source = 'manual',
    String? sourceRef,
    String? detail,
    bool confirmed = true,
  }) async {
    final now = DateTime.now();
    await _db.into(_db.todoItems).insert(
          TodoItemsCompanion.insert(
            id: '${now.microsecondsSinceEpoch}',
            title: title.trim(),
            dueAt: Value(dueAt),
            courseId: Value(courseId),
            source: Value(source),
            sourceRef: Value(sourceRef),
            detail: Value(detail),
            confirmed: Value(confirmed),
          ),
        );
  }

  Future<void> toggle(TodoItem item) async {
    final done = item.status == 'open';
    await (_db.update(_db.todoItems)..where((t) => t.id.equals(item.id))).write(
      TodoItemsCompanion(
        status: Value(done ? 'done' : 'open'),
        completedAt: Value(done ? DateTime.now() : null),
      ),
    );
  }

  Future<void> delete(TodoItem item) async {
    await (_db.delete(_db.todoItems)..where((t) => t.id.equals(item.id))).go();
  }

  /// 同一来源的同一条目不重复入库（SPEC §4.3 去重）。
  Future<TodoItem?> findBySourceRef(String source, String sourceRef) {
    final query = _db.select(_db.todoItems)
      ..where((t) => t.source.equals(source))
      ..where((t) => t.sourceRef.equals(sourceRef));
    return query.getSingleOrNull();
  }
}

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final todoRepositoryProvider = Provider<TodoRepository>(
  (ref) => TodoRepository(ref.watch(databaseProvider)),
);

final todoListProvider = StreamProvider<List<TodoItem>>(
  (ref) => ref.watch(todoRepositoryProvider).watchOpen(),
);
