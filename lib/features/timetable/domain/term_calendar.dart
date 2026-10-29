/// 教学周 ↔ 真实日期的映射（Dart 版，移植自 TJTimetable `domain/TermCalendar.kt`）。
///
/// 注意 [firstWeekStart] 是"教学周第 1 周的周一"，不一定是 API 返回的
/// `beginDay`（那常是报到日）：用 [TermCalendar.fromApi] 会向后对齐到周一。
library;

class TermCalendar {
  const TermCalendar({
    required this.calendarId,
    required this.name,
    required this.year,
    required this.term,
    required this.firstWeekStart,
    required this.endDate,
    required this.totalWeeks,
    this.weekStartDay = DateTime.monday,
    this.isCurrent = false,
  });

  /// 学期编号（教务 API 的 calendarId）。
  final String calendarId;

  /// 如 `2025-2026学年度第2学期`。
  final String name;

  final int year;

  /// 1 = 秋季, 2 = 春季, 3 = 暑期。
  final int term;

  /// 教学周第 1 周的第一天（周一）。
  final DateTime firstWeekStart;

  /// 学期最后一天。
  final DateTime endDate;

  final int totalWeeks;

  /// 教学周从周几开始（同济是周一）。
  final int weekStartDay;

  final bool isCurrent;

  DateTime weekStart(int week) =>
      firstWeekStart.add(Duration(days: 7 * (week - 1)));

  DateTime weekEnd(int week) => weekStart(week).add(const Duration(days: 6));

  /// 第 [week] 周的周 [dayOfWeek]（DateTime.monday=1 … sunday=7）。
  DateTime dateOf(int week, int dayOfWeek) {
    final offset = ((dayOfWeek - weekStartDay) + 7) % 7;
    return weekStart(week).add(Duration(days: offset));
  }

  /// [date] 落在第几教学周；学期外返回 null。
  int? weekOf(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(firstWeekStart).inDays;
    if (diff < 0) return null;
    final week = diff ~/ 7 + 1;
    return (week >= 1 && week <= totalWeeks) ? week : null;
  }

  bool contains(DateTime date) => weekOf(date) != null;

  List<int> get weeks => List.generate(totalWeeks, (i) => i + 1);

  /// 如 `3.2 – 3.8`。
  String weekLabel(int week) {
    final s = weekStart(week);
    final e = weekEnd(week);
    return '${s.month}.${s.day} – ${e.month}.${e.day}';
  }

  /// 用教务 API 字段构造；beginDay 向后对齐到周一（报到日也在第 1 周内）。
  factory TermCalendar.fromApi({
    required String calendarId,
    required String name,
    required int year,
    required int term,
    required DateTime beginDay,
    required DateTime endDay,
    required int totalWeeks,
    bool isCurrent = true,
  }) {
    final offset = (beginDay.weekday - DateTime.monday + 7) % 7;
    final monday = DateTime(
      beginDay.year,
      beginDay.month,
      beginDay.day,
    ).subtract(Duration(days: offset));
    final clampedWeeks = totalWeeks < 1
        ? 1
        : (totalWeeks > 64 ? 64 : totalWeeks);
    return TermCalendar(
      calendarId: calendarId,
      name: name,
      year: year,
      term: term,
      firstWeekStart: monday,
      endDate: endDay,
      totalWeeks: clampedWeeks,
      isCurrent: isCurrent,
    );
  }
}

/// 课表要画的 weekday 列（左到右）。startOnToday 时把今天转到首列（手机窄屏体验）。
List<int> weekdayColumns({
  required bool showWeekend,
  required bool startOnToday,
  required DateTime today,
}) {
  final base = List.generate(showWeekend ? 7 : 5, (i) => i + 1); // 1=Mon
  if (!startOnToday) return base;
  final index = base.indexOf(today.weekday);
  if (index <= 0) return base;
  return [...base.sublist(index), ...base.sublist(0, index)];
}

/// [days] 中"今天"所在列的下标；不在本周（或今天被隐藏的周末列）返回 -1。
/// 必须按解析后的日期比较，不能按 weekday 比——否则翻到哪周都在高亮周二。
int todayColumn({
  required TermCalendar term,
  required int week,
  required List<int> days,
  required DateTime today,
}) {
  final t = DateTime(today.year, today.month, today.day);
  for (var i = 0; i < days.length; i++) {
    final d = term.dateOf(week, days[i]);
    if (DateTime(d.year, d.month, d.day) == t) return i;
  }
  return -1;
}
