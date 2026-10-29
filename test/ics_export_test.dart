import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/core/database/database.dart';
import 'package:jinah/features/timetable/domain/term_calendar.dart';
import 'package:jinah/features/timetable/export/ics_export.dart';

void main() {
  final term = TermCalendar.fromApi(
    calendarId: '100',
    name: '2026春',
    year: 2026,
    term: 2,
    beginDay: DateTime(2026, 2, 23), // 周一
    endDay: DateTime(2026, 7, 5),
    totalWeeks: 18,
  );

  final course = Course(
    id: 'c1',
    name: '大学物理(上)',
    source: 'manual',
    createdAt: DateTime(2026, 10, 30),
  );

  ScheduleEntry entry({
    required int weekday,
    required int start,
    required int end,
    required int weekBits,
  }) =>
      ScheduleEntry(
        id: 'e$weekday-$start',
        termId: '100',
        courseId: 'c1',
        weekday: weekday,
        startPeriod: start,
        endPeriod: end,
        weekBits: weekBits,
        weekCanonical: '',
        rawWeekText: '',
        source: 'manual',
        sourceRef: null,
        location: '瑞安楼 201',
      );

  group('buildTimetableIcs', () {
    test('普通连续周段：INTERVAL=1，COUNT=周数', () {
      final ics = buildTimetableIcs(
        term: term,
        courses: {'c1': course},
        entries: [entry(weekday: 1, start: 1, end: 2, weekBits: 0x07)],
        now: DateTime(2026, 10, 30, 12),
      );
      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('TZID:Asia/Shanghai'));
      expect(ics, contains('RRULE:FREQ=WEEKLY;INTERVAL=1;COUNT=3'));
      // 第 1 周周一 1-2 节：08:00-09:35
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260223T080000'));
      expect(ics, contains('DTEND;TZID=Asia/Shanghai:20260223T093500'));
      expect(ics, contains('SUMMARY:大学物理(上)'));
      expect(ics, contains('LOCATION:瑞安楼 201'));
      expect(ics, contains('END:VCALENDAR'));
    });

    test('单周模式拆成多个固定日期事件（无 RRULE）', () {
      // 第 1、3、5 周 → 0x15：ranges 为三个单周段
      final ics = buildTimetableIcs(
        term: term,
        courses: {'c1': course},
        entries: [entry(weekday: 2, start: 3, end: 4, weekBits: 0x15)],
        now: DateTime(2026, 10, 30, 12),
      );
      expect(ics, isNot(contains('RRULE')));
      expect(ics.split('BEGIN:VEVENT').length - 1, 3);
      // 第 1/3/5 周周二 3-4 节：10:00 开始
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260224T100000'));
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260310T100000'));
      expect(ics, contains('DTSTART;TZID=Asia/Shanghai:20260324T100000'));
    });

    test('单一周无 RRULE', () {
      final ics = buildTimetableIcs(
        term: term,
        courses: {'c1': course},
        entries: [entry(weekday: 3, start: 5, end: 6, weekBits: 0x04)],
        now: DateTime(2026, 10, 30, 12),
      );
      expect(ics, isNot(contains('RRULE')));
      expect(ics.split('BEGIN:VEVENT').length - 1, 1);
    });

    test('连续周段用 RRULE 周重复', () {
      final ics = buildTimetableIcs(
        term: term,
        courses: {'c1': course},
        entries: [entry(weekday: 4, start: 7, end: 8, weekBits: 0x07)], // 1-3 周
        now: DateTime(2026, 10, 30, 12),
      );
      expect(ics.split('BEGIN:VEVENT').length - 1, 1);
      expect(ics, contains('RRULE:FREQ=WEEKLY;INTERVAL=1;COUNT=3'));
    });

    test('ICS 文本转义', () {
      expect(icsEscape('a,b;c\\d\ne'), 'a\\,b\\;c\\\\d\\ne');
    });
  });
}
