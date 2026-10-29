import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../todo/data/course_repository.dart';
import '../../todo/data/todo_repository.dart';
import '../domain/term_calendar.dart';

class TimetableRepository {
  TimetableRepository(this._db);

  final AppDatabase _db;

  /// 当前学期（没有则 null）。
  Stream<Term?> watchCurrentTerm() {
    final query = _db.select(_db.terms)
      ..where((t) => t.isCurrent.equals(true))
      ..limit(1);
    return query.watchSingleOrNull();
  }

  Stream<List<ScheduleEntry>> watchEntries(String termId) =>
      (_db.select(_db.scheduleEntries)
            ..where((e) => e.termId.equals(termId)))
          .watch();

  /// 同一学期同一来源的旧条目整体替换（重新导入不产生重复）。
  Future<void> replaceEntriesForSource({
    required String source,
    required String termId,
    required List<ScheduleEntriesCompanion> entries,
  }) async {
    await (_db.delete(_db.scheduleEntries)
          ..where((e) => e.source.equals(source))
          ..where((e) => e.termId.equals(termId)))
        .go();
    if (entries.isNotEmpty) {
      await _db.batch((b) => b.insertAll(_db.scheduleEntries, entries));
    }
  }

  Future<Term> upsertTerm(TermCalendar calendar) async {
    await _db.into(_db.terms).insertOnConflictUpdate(
          TermsCompanion(
            id: Value(calendar.calendarId),
            name: Value(calendar.name),
            year: Value(calendar.year),
            termIndex: Value(calendar.term),
            firstWeekStart: Value(calendar.firstWeekStart),
            endDate: Value(calendar.endDate),
            totalWeeks: Value(calendar.totalWeeks),
            isCurrent: Value(calendar.isCurrent),
          ),
        );
    return Term(
      id: calendar.calendarId,
      name: calendar.name,
      year: calendar.year,
      termIndex: calendar.term,
      firstWeekStart: calendar.firstWeekStart,
      endDate: calendar.endDate,
      totalWeeks: calendar.totalWeeks,
      isCurrent: calendar.isCurrent,
    );
  }
}

final timetableRepositoryProvider = Provider<TimetableRepository>(
  (ref) => TimetableRepository(ref.watch(databaseProvider)),
);

/// 视图模型：当前学期 + 用户选中的周（null = 跟随"今天"所在的周）。
final currentTermProvider = StreamProvider<Term?>(
  (ref) => ref.watch(timetableRepositoryProvider).watchCurrentTerm(),
);

final selectedWeekProvider = NotifierProvider<SelectedWeek, int?>(
  SelectedWeek.new,
);

class SelectedWeek extends Notifier<int?> {
  @override
  int? build() => null; // null → 自动跟随今天

  void set(int? week) => state = week;
}

/// 选中周的课表条目（已按周位掩码过滤）。
final weekEntriesProvider = FutureProvider<List<ScheduleEntry>>((ref) async {
  final term = await ref.watch(currentTermProvider.future);
  if (term == null) return const [];
  final entries = await ref
      .watch(timetableRepositoryProvider)
      .watchEntries(term.id)
      .first;
  final week = ref.watch(selectedWeekProvider) ??
      TermCalendar(
        calendarId: term.id,
        name: term.name,
        year: term.year,
        term: term.termIndex,
        firstWeekStart: term.firstWeekStart,
        endDate: term.endDate,
        totalWeeks: term.totalWeeks,
        isCurrent: term.isCurrent,
      ).weekOf(DateTime.now()) ??
      1;
  return entries.where((e) => e.weekBits & (1 << (week - 1)) != 0).toList();
});

/// 课程 id → Course 的映射（名称、颜色）。
final coursesMapProvider = StreamProvider<Map<String, Course>>((ref) {
  return ref.watch(courseRepositoryProvider).watchAll().map(
        (list) => {for (final c in list) c.id: c},
      );
});
