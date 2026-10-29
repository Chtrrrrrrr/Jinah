/// 1系统课表捕获响应的解析（纯函数，移植自 TJTimetable `TongjiStudentAdapter.kt`）。
///
/// 兼容三种真实形状（自动探测）：
/// - 选课服务 `getDataBk`：`data.selectedCourses[].course{ times[] }`
/// - 开放平台/报表：`data[].timeTableList[]`
/// - 排课服务扁平：`data[]{ weekState 位掩码 }`
library;

import 'dart:convert';

import '../domain/week_pattern.dart';

const fallbackTotalWeeks = 16;

class ImportedSession {
  ImportedSession({
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
    this.room,
    this.rawWeeks = '',
  });

  final int day; // 1=周一 … 7=周日
  final int startPeriod;
  final int endPeriod;
  final WeekPattern weeks;
  final String? room;
  final String rawWeeks;
}

class ImportedCourse {
  ImportedCourse({
    required this.id,
    required this.name,
    this.courseCode,
    this.teachingClassCode,
    this.teacher,
    this.campus,
    this.sessions = const [],
  });

  final String id;
  final String name;
  final String? courseCode;
  final String? teachingClassCode;
  final String? teacher;
  final String? campus;
  final List<ImportedSession> sessions;
}

class ImportedTimetable {
  ImportedTimetable({
    this.calendarId,
    this.calendarName,
    this.courses = const [],
  });

  final String? calendarId;
  final String? calendarName;
  final List<ImportedCourse> courses;

  int get sessionCount =>
      courses.fold(0, (sum, c) => sum + c.sessions.length);
}

/// 这段文本像不像课表响应（0.0-1.0，移植自 Adapter 的探测启发式）。
double looksLikeTimetable(String text) {
  if (!text.contains('selectedCourses') &&
      !text.contains('weekState') &&
      !text.contains('timeTableList')) {
    return 0.0;
  }
  final decoded = _tryDecode(text);
  if (decoded == null) return 0.5;
  final data = _unwrap(decoded);
  if (data is Map && data['selectedCourses'] is List) return 0.98;
  if (data is List &&
      data.any((e) =>
          e is Map && e.containsKey('weekState') && e.containsKey('dayOfWeek'))) {
    return 0.9;
  }
  return 0.5;
}

/// 解析捕获到的课表响应；不是课表则返回 null，结构坏则尽量返回解析出的部分。
ImportedTimetable? parseCapturedTimetable(String text) {
  final decoded = _tryDecode(text);
  if (decoded == null) return null;
  final data = _unwrap(decoded);
  if (data == null) return null;

  // 形状一：选课服务 selectedCourses
  if (data is Map && data['selectedCourses'] is List) {
    return _fromSelectedCourses(data);
  }
  // 形状二/三：timeTableList 嵌套 或 扁平 weekState
  if (data is List) {
    if (data.any((e) => e is Map && e.containsKey('timeTableList'))) {
      return _fromTimeTableList(data);
    }
    if (data.any((e) => e is Map && e.containsKey('weekState'))) {
      return _fromFlat(data);
    }
  }
  return null;
}

// -------------------------------------------------------------- 形状一

ImportedTimetable _fromSelectedCourses(Map<dynamic, dynamic> data) {
  final courses = <ImportedCourse>[];
  String? calendarId = data['calendarId']?.toString();
  String? calendarName;

  for (final entry in data['selectedCourses'] as List) {
    if (entry is! Map) continue;
    final course = entry['course'];
    if (course is! Map) continue;
    calendarId ??= course['calendarId']?.toString();
    calendarName ??= course['calendarName']?.toString();

    final teachers = <String>{};
    final sessions = _mergeTimes(course['times'], teachers);
    if (sessions.isEmpty) continue;

    courses.add(ImportedCourse(
      id: course['teachClassId']?.toString() ??
          course['teachClassCode']?.toString() ??
          course['courseCode']?.toString() ??
          'unknown',
      name: course['courseName']?.toString() ?? '(未知课程)',
      courseCode: course['courseCode']?.toString(),
      teachingClassCode: course['teachClassCode']?.toString(),
      teacher: teachers.isEmpty ? null : teachers.join(', '),
      sessions: sessions,
    ));
  }

  return ImportedTimetable(
    calendarId: calendarId,
    calendarName: calendarName,
    courses: _sortCourses(courses),
  );
}

// -------------------------------------------------------------- 形状二

ImportedTimetable _fromTimeTableList(List<dynamic> data) {
  final courses = <ImportedCourse>[];
  String? calendarId;
  String? calendarName;

  for (final item in data) {
    if (item is! Map) continue;
    final times = item['timeTableList'];
    if (times is! List) continue;

    final teachers = <String>{};
    final sessions = _mergeTimes(times, teachers);
    if (sessions.isEmpty) continue;

    courses.add(ImportedCourse(
      id: item['teachingClassId']?.toString() ??
          item['classCode']?.toString() ??
          item['courseCode']?.toString() ??
          'unknown',
      name: item['courseName']?.toString() ?? '(未知课程)',
      courseCode: item['courseCode']?.toString(),
      teachingClassCode: item['classCode']?.toString(),
      teacher: teachers.isEmpty
          ? (item['teacherName']?.toString())
          : teachers.join(', '),
      campus: item['campus']?.toString(),
      sessions: sessions,
    ));
  }

  return ImportedTimetable(
    calendarId: calendarId,
    calendarName: calendarName,
    courses: _sortCourses(courses),
  );
}

// -------------------------------------------------------------- 形状三（扁平 weekState 掩码）

ImportedTimetable _fromFlat(List<dynamic> data) {
  final byId = <String, ImportedCourse>{};
  final order = <String>[];

  for (final row in data) {
    if (row is! Map) continue;
    final day = _toInt(row['dayOfWeek']);
    final start = _toInt(row['timeStart']);
    final end = _toInt(row['timeEnd']);
    final weekState = _toInt(row['weekState']);
    if (day == null || start == null || end == null || weekState == null) {
      continue;
    }
    if (day < 1 || day > 7) continue;

    final courseCode = row['courseCode']?.toString();
    final classCode = row['code']?.toString();
    final id = row['teachingClassId']?.toString() ??
        classCode ??
        '${courseCode ?? 'unknown'}-$day-$start';

    final course = byId.putIfAbsent(id, () {
      order.add(id);
      final teachers = <String>{
        ..._parseTeachersFromValue(
            row['value']?.toString() ?? row['newValue']?.toString()),
      };
      if (row['teacherCodes'] is List) {
        for (final t in row['teacherCodes'] as List) {
          final s = t?.toString().trim();
          if (s != null && s.isNotEmpty) teachers.add(s);
        }
      }
      return ImportedCourse(
        id: id,
        name: row['courseName']?.toString() ?? '(未知课程)',
        courseCode: courseCode,
        teachingClassCode: classCode,
        teacher: teachers.isEmpty ? null : teachers.join(', '),
        campus: row['campusI18n']?.toString(),
        sessions: <ImportedSession>[],
      );
    });

    // weekState 是无符号 32 位掩码：bit0 = 第 1 周
    final mask = weekState & 0xFFFFFFFF;
    final session = ImportedSession(
      day: day,
      startPeriod: start,
      endPeriod: end,
      weeks: WeekPattern.fromBits(mask),
      room: row['roomName']?.toString(),
      rawWeeks: 'weekState=$weekState',
    );
    final key =
        '${session.day}-${session.startPeriod}-${session.endPeriod}-$mask';
    if (course.sessions.any((s) =>
        '${s.day}-${s.startPeriod}-${s.endPeriod}-${s.weeks.bits}' == key)) {
      continue;
    }
    course.sessions.add(session);
  }

  final courses = order.map((id) => byId[id]!).toList()
    ..forEach((c) => c.sessions.sort((a, b) =>
        a.day != b.day
            ? a.day.compareTo(b.day)
            : a.startPeriod.compareTo(b.startPeriod)));
  return ImportedTimetable(courses: _sortCourses(courses));
}

// -------------------------------------------------------------- 共用

/// times[] 解析 + 同格合并（同天同节次同教室 → 周次取并集）。
/// 典型场景：按周换老师的课，不合并会叠出一堆色块。
List<ImportedSession> _mergeTimes(List<dynamic> times, Set<String> teachers) {
  final sessions = <ImportedSession>[];
  final indexByKey = <String, int>{};

  for (final time in times) {
    if (time is! Map) continue;
    final day = _toInt(time['dayOfWeek']);
    final start = _toInt(time['timeStart']);
    final end = _toInt(time['timeEnd']);
    if (day == null || start == null || end == null) continue;
    if (day < 1 || day > 7) continue;

    // 教师：姓名 / 姓名(工号) / value 文本
    for (final t in _parseTeachersFromValue(
        time['value']?.toString() ?? time['newValue']?.toString())) {
      teachers.add(t);
    }
    final single = time['teacherName']?.toString() ??
        time['teacherCodeI18n']?.toString();
    final code = time['teacherCode']?.toString();
    if (single != null && single.isNotEmpty) {
      teachers.add(code != null && code.isNotEmpty ? '$single($code)' : single);
    }

    final weeksElement = time['weeks'];
    final weekList = weeksElement is List ? weeksElement : null;
    final weeks = (weekList != null && weekList.isNotEmpty)
        ? WeekPattern.of(weekList.map((e) => _toInt(e) ?? 0))
        : WeekPattern.range(1, fallbackTotalWeeks);

    final room = _firstNonEmpty([
      time['roomIdI18n']?.toString(),
      time['roomLable']?.toString(),
      time['classRoomName']?.toString(),
    ]);
    final key = '$day-$start-$end-${room ?? ''}';

    final existing = indexByKey[key];
    if (existing != null) {
      final prior = sessions[existing];
      sessions[existing] = ImportedSession(
        day: prior.day,
        startPeriod: prior.startPeriod,
        endPeriod: prior.endPeriod,
        weeks: prior.weeks + weeks,
        room: prior.room,
        rawWeeks: prior.rawWeeks,
      );
      continue;
    }

    indexByKey[key] = sessions.length;
    sessions.add(ImportedSession(
      day: day,
      startPeriod: start,
      endPeriod: end,
      weeks: weeks,
      room: room,
      rawWeeks: weeksElement?.toString() ?? '',
    ));
  }

  sessions.sort((a, b) => a.day != b.day
      ? a.day.compareTo(b.day)
      : a.startPeriod.compareTo(b.startPeriod));
  return sessions;
}

/// value 文本里的教师名解析（"张三、李四" / "张三,李四"）。
List<String> _parseTeachersFromValue(String? value) {
  if (value == null) return const [];
  return value
      .split(RegExp(r'[、,，;/；]'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

String? _firstNonEmpty(List<String?> values) {
  for (final v in values) {
    if (v != null && v.isNotEmpty) return v;
  }
  return null;
}

List<ImportedCourse> _sortCourses(List<ImportedCourse> courses) {
  courses.sort((a, b) => a.name.compareTo(b.name));
  return courses;
}

Object? _unwrap(Object? decoded) {
  if (decoded is Map && decoded.containsKey('data')) return decoded['data'];
  return decoded;
}

Object? _tryDecode(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

int? _toInt(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
