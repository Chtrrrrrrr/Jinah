import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import 'todo_repository.dart';

class CourseRepository {
  CourseRepository(this._db);

  final AppDatabase _db;

  Stream<List<Course>> watchAll() => _db.select(_db.courses).watch();

  /// 按来源 upsert：同一来源同一 sourceRef 的课程只更新名称，不重复建。
  Future<Course> upsertFromSource({
    required String source,
    required String sourceRef,
    required String name,
  }) async {
    final existing = await (_db.select(_db.courses)
          ..where((c) => c.source.equals(source))
          ..where((c) => c.sourceRef.equals(sourceRef)))
        .getSingleOrNull();

    if (existing != null) {
      if (existing.name != name) {
        await (_db.update(_db.courses)..where((c) => c.id.equals(existing.id)))
            .write(CoursesCompanion(name: Value(name)));
      }
      return existing;
    }

    final id = '${source}_$sourceRef';
    await _db.into(_db.courses).insert(
          CoursesCompanion.insert(
            id: id,
            name: name,
            source: Value(source),
            sourceRef: Value(sourceRef),
          ),
        );
    return Course(
      id: id,
      name: name,
      source: source,
      sourceRef: sourceRef,
      createdAt: DateTime.now(),
    );
  }
}

final courseRepositoryProvider = Provider<CourseRepository>(
  (ref) => CourseRepository(ref.watch(databaseProvider)),
);
