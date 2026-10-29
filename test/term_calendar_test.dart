import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/features/timetable/domain/term_calendar.dart';

/// 移植自 TJTimetable `TermCalendarTest.kt` 的核心语义。
void main() {
  // 2026 春季学期：2 月 23 日（周一）开学，18 个教学周
  TermCalendar buildTerm() => TermCalendar.fromApi(
        calendarId: '100',
        name: '2025-2026学年度第2学期',
        year: 2025,
        term: 2,
        beginDay: DateTime(2026, 2, 23),
        endDay: DateTime(2026, 7, 5),
        totalWeeks: 18,
      );

  group('周与日期换算', () {
    test('weekOf：开学第一天是第 1 周', () {
      expect(buildTerm().weekOf(DateTime(2026, 2, 23)), 1);
    });

    test('weekOf：周末属于同一周（周日是第 7 天）', () {
      expect(buildTerm().weekOf(DateTime(2026, 3, 1)), 1); // 周日
    });

    test('weekOf：跨周边界', () {
      expect(buildTerm().weekOf(DateTime(2026, 3, 2)), 2); // 次周周一
    });

    test('weekOf：学期外返回 null', () {
      expect(buildTerm().weekOf(DateTime(2026, 2, 20)), isNull); // 开学前
      expect(buildTerm().weekOf(DateTime(2026, 7, 6)), isNull); // 结束后
    });

    test('dateOf 与 weekOf 互逆', () {
      final term = buildTerm();
      for (var w = 1; w <= 18; w++) {
        for (var d = 1; d <= 7; d++) {
          expect(term.weekOf(term.dateOf(w, d)), w);
        }
      }
    });

    test('weekStart 与 weekEnd', () {
      final term = buildTerm();
      expect(term.weekStart(1), DateTime(2026, 2, 23));
      expect(term.weekEnd(1), DateTime(2026, 3, 1));
      expect(term.weekStart(3), DateTime(2026, 3, 9));
    });

    test('weekLabel', () {
      expect(buildTerm().weekLabel(1), '2.23 – 3.1');
    });
  });

  group('fromApi 对齐到周一', () {
    test('beginDay 是周中时向后对齐（报到日也落在第 1 周）', () {
      final term = TermCalendar.fromApi(
        calendarId: '100',
        name: 'x',
        year: 2025,
        term: 1,
        beginDay: DateTime(2026, 9, 9), // 周三
        endDay: DateTime(2027, 1, 20),
        totalWeeks: 16,
      );
      expect(term.firstWeekStart, DateTime(2026, 9, 7)); // 前一个周一
      expect(term.weekOf(DateTime(2026, 9, 9)), 1);
    });

    test('beginDay 正好是周一时不动', () {
      final term = TermCalendar.fromApi(
        calendarId: '100',
        name: 'x',
        year: 2025,
        term: 1,
        beginDay: DateTime(2026, 9, 7),
        endDay: DateTime(2027, 1, 20),
        totalWeeks: 16,
      );
      expect(term.firstWeekStart, DateTime(2026, 9, 7));
    });
  });

  group('weekdayColumns / todayColumn', () {
    test('默认周一开头，隐藏周末', () {
      expect(
        weekdayColumns(
          showWeekend: false,
          startOnToday: false,
          today: DateTime(2026, 10, 29),
        ),
        [1, 2, 3, 4, 5],
      );
    });

    test('startOnToday 把今天转到首列', () {
      expect(
        weekdayColumns(
          showWeekend: false,
          startOnToday: true,
          today: DateTime(2026, 10, 29), // 周四
        ),
        [4, 5, 1, 2, 3],
      );
    });

    test('今天不在本周时 todayColumn 返回 -1', () {
      final term = buildTerm();
      expect(
        todayColumn(
          term: term,
          week: 5,
          days: [1, 2, 3, 4, 5],
          today: DateTime(2026, 2, 23), // 第 1 周的日期看第 5 周
        ),
        -1,
      );
    });

    test('todayColumn 按日期而非 weekday 命中', () {
      final term = buildTerm();
      // 2026-10-29 是第 19 周外……用开学周：2-25 周三，第 1 周
      expect(
        todayColumn(
          term: term,
          week: 1,
          days: [1, 2, 3, 4, 5],
          today: DateTime(2026, 2, 25),
        ),
        2, // 第 3 列
      );
    });
  });
}
