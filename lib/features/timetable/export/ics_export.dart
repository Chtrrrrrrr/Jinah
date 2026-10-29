/// 课表 → iCalendar（RFC 5545）。每个时段按连续周段展开为 VEVENT：
/// 单周段就是一个固定日期事件（无 RRULE），连续段用 RRULE WEEKLY 重复。
///
/// 注：单/双周模式的周集合（如 1,3,5,7）在 ranges() 里天然拆成多个单周段，
/// 展开为多个固定日期事件，比依赖 RRULE 奇偶性更可靠。
///
/// 时段时刻来自同济节次表（Asia/Shanghai 本地时间 + TZID，不做 UTC 换算）。
library;

import '../../../core/database/database.dart';
import '../domain/period_slots.dart';
import '../domain/term_calendar.dart';
import '../domain/week_pattern.dart';

String buildTimetableIcs({
  required TermCalendar term,
  required Map<String, Course> courses,
  required List<ScheduleEntry> entries,
  DateTime? now,
}) {
  final stamp = _utcStamp(now ?? DateTime.now());
  final buf = StringBuffer()
    ..writeAll(_lines([
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Jinah//Timetable//CN',
      'CALSCALE:GREGORIAN',
      'X-WR-CALNAME:Jinah 课表',
      'BEGIN:VTIMEZONE',
      'TZID:Asia/Shanghai',
      'BEGIN:STANDARD',
      'TZOFFSETFROM:+0800',
      'TZOFFSETTO:+0800',
      'TZNAME:CST',
      'DTSTART:19700101T000000',
      'END:STANDARD',
      'END:VTIMEZONE',
    ]));

  for (final e in entries) {
    final course = courses[e.courseId];
    final weeks = WeekPattern.fromBits(e.weekBits);
    final beginSlot = slotFor(e.startPeriod);
    final endSlot = slotFor(e.endPeriod);
    if (beginSlot == null || endSlot == null) continue;

    for (final (first, last) in weeks.ranges()) {
      final count = last - first + 1;
      final startDate = term.dateOf(first, e.weekday);
      final endDate = term.dateOf(first, e.weekday);

      buf.writeAll(_lines([
        'BEGIN:VEVENT',
        'UID:${_uid(e.id, first, last)}@jinah',
        'DTSTAMP:$stamp',
        'DTSTART;TZID=Asia/Shanghai:${_dt(startDate, beginSlot.begin)}',
        'DTEND;TZID=Asia/Shanghai:${_dt(endDate, endSlot.end)}',
        if (count > 1) 'RRULE:FREQ=WEEKLY;INTERVAL=1;COUNT=$count',
        'SUMMARY:${icsEscape(course?.name ?? '未绑定课程')}',
        if (e.location != null && e.location!.isNotEmpty)
          'LOCATION:${icsEscape(e.location!)}',
        if (course?.teacher != null && course!.teacher!.isNotEmpty)
          'DESCRIPTION:${icsEscape('教师：${course.teacher} · ${weeks.display()}')}'
        else
          'DESCRIPTION:${icsEscape(weeks.display())}',
        'END:VEVENT',
      ]));
    }
  }

  buf.writeAll(_lines(['END:VCALENDAR']));
  return buf.toString();
}

/// ICS 文本转义（RFC 5545 §3.3.11）。
String icsEscape(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\n', '\\n');

String _dt(DateTime d, String hm) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}T'
    '${hm.replaceAll(':', '')}00';

String _utcStamp(DateTime d) {
  final u = d.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      'T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

String _uid(String entryId, int first, int last) =>
    '$entryId-w$first-$last'.replaceAll(RegExp(r'[^A-Za-z0-9\-@]'), '-');

Iterable<String> _lines(Iterable<String> items) =>
    items.map((l) => '$l\r\n');
