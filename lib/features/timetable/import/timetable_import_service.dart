import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database.dart';
import '../../todo/data/course_repository.dart';
import '../data/timetable_repository.dart';
import '../domain/term_calendar.dart';
import 'capture_parser.dart';
import 'open_platform_api.dart';

sealed class TimetableImportResult {
  const TimetableImportResult();

  String describe() => switch (this) {
        ImportNoData() => '没有从响应中解析到课程',
        ImportFailure(:final message) => '导入失败：$message',
        ImportOk(:final courses, :final sessions, :final termName) =>
          '已导入 $courses 门课（$sessions 个时段）${termName == null ? '' : ' · $termName'}',
      };
}

class ImportOk extends TimetableImportResult {
  const ImportOk({
    required this.courses,
    required this.sessions,
    this.termName,
  });

  final int courses;
  final int sessions;
  final String? termName;
}

class ImportNoData extends TimetableImportResult {
  const ImportNoData();
}

class ImportFailure extends TimetableImportResult {
  const ImportFailure(this.message);

  final String message;
}

/// 把解析出的课表落库：课程 upsert → 学期确定 → 旧条目整体替换。
class TimetableImportService {
  TimetableImportService(
    this._courses,
    this._timetable,
    this._openPlatform,
  );

  final CourseRepository _courses;
  final TimetableRepository _timetable;
  final OpenPlatformApi _openPlatform;

  Future<TimetableImportResult> importCaptured(
    ImportedTimetable data, {
    required String source,
  }) async {
    if (data.courses.isEmpty) return const ImportNoData();

    try {
      // 课程 upsert（sourceRef = 教学班 id，重复导入不产生副本）
      final localCourses = <String, Course>{};
      for (final c in data.courses) {
        final local = await _courses.upsertFromSource(
          source: source,
          sourceRef: c.id,
          name: c.name,
        );
        localCourses[c.id] = local;
      }

      // 学期：用 calendarId 从开放平台公开接口补日期；失败则用"未知学期"退化
      Term term;
      String? termName;
      final calendarId = data.calendarId;
      if (calendarId != null) {
        final cal = await _openPlatform.termCalendarFor(calendarId);
        if (cal != null) {
          term = await _timetable.upsertTerm(cal);
          termName = cal.name;
        } else {
          term = await _fallbackTerm(calendarId, data.calendarName);
        }
      } else {
        term = await _fallbackTerm('unknown', data.calendarName);
      }

      // 条目整体替换
      final entries = <ScheduleEntriesCompanion>[];
      var n = 0;
      for (final c in data.courses) {
        final local = localCourses[c.id]!;
        for (final s in c.sessions) {
          entries.add(ScheduleEntriesCompanion(
            id: Value('${local.id}-$source-${n++}'),
            termId: Value(term.id),
            courseId: Value(local.id),
            weekday: Value(s.day),
            startPeriod: Value(s.startPeriod),
            endPeriod: Value(s.endPeriod),
            weekBits: Value(s.weeks.bits),
            weekCanonical: Value(s.weeks.canonical()),
            rawWeekText: Value(s.rawWeeks),
            location: Value(s.room),
            source: Value(source),
            sourceRef: Value('${c.id}-${s.day}-${s.startPeriod}-${s.endPeriod}'),
          ));
        }
      }
      await _timetable.replaceEntriesForSource(
        source: source,
        termId: term.id,
        entries: entries,
      );

      return ImportOk(
        courses: data.courses.length,
        sessions: data.sessionCount,
        termName: termName,
      );
    } catch (e) {
      return ImportFailure(e.toString());
    }
  }

  Future<Term> _fallbackTerm(String calendarId, String? name) =>
      _timetable.upsertTerm(TermCalendar(
        calendarId: calendarId,
        name: name ?? '未知学期',
        year: DateTime.now().year,
        term: 1,
        // 无日期信息时退化：以今天所在周为第 1 周，16 周
        firstWeekStart: DateTime.now()
            .subtract(Duration(days: DateTime.now().weekday - 1)),
        endDate: DateTime.now().add(const Duration(days: 16 * 7)),
        totalWeeks: 16,
        isCurrent: true,
      ));
}

final timetableImportServiceProvider = Provider<TimetableImportService>(
  (ref) => TimetableImportService(
    ref.watch(courseRepositoryProvider),
    ref.watch(timetableRepositoryProvider),
    ref.watch(openPlatformApiProvider),
  ),
);
