import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/features/timetable/domain/week_pattern.dart';
import 'package:jinah/features/timetable/import/capture_parser.dart';

void main() {
  group('形状一：selectedCourses（选课服务）', () {
    // 结构样例来自 TJTimetable TongjiStudentAdapter 的文档注释
    const sample = '''
    {
      "code": "0",
      "data": {
        "calendarId": 122,
        "selectedCourses": [
          {
            "course": {
              "courseName": "测试课程A",
              "courseCode": "TSTA001",
              "teachClassId": 9000000000000011,
              "teachClassCode": "TSTA0A01",
              "times": [
                {
                  "dayOfWeek": 4,
                  "timeStart": 5,
                  "timeEnd": 6,
                  "weeks": [1, 3, 5],
                  "roomIdI18n": "测试楼201",
                  "teacherCodeI18n": "测试教师甲",
                  "teacherCode": "10001"
                }
              ]
            }
          }
        ]
      }
    }
    ''';

    test('解析课程/时段/教室/教师，并接出 calendarId', () {
      final result = parseCapturedTimetable(sample);
      expect(result, isNotNull);
      expect(result!.calendarId, '122');
      expect(result.courses.length, 1);

      final course = result.courses.single;
      expect(course.name, '测试课程A');
      expect(course.courseCode, 'TSTA001');
      expect(course.id, '9000000000000011');
      expect(course.teacher, '测试教师甲(10001)');

      expect(course.sessions.length, 1);
      final s = course.sessions.single;
      expect(s.day, 4);
      expect(s.startPeriod, 5);
      expect(s.endPeriod, 6);
      expect(s.weeks.weekNumbers, [1, 3, 5]);
      expect(s.room, '测试楼201');
    });

    test('同格多条 times（按周换老师）合并为一块、周次取并集', () {
      const merged = '''
      {
        "data": {
          "selectedCourses": [
            {
              "course": {
                "courseName": "换师课",
                "teachClassId": 1,
                "times": [
                  {"dayOfWeek": 1, "timeStart": 1, "timeEnd": 2, "weeks": [10], "roomIdI18n": "A101"},
                  {"dayOfWeek": 1, "timeStart": 1, "timeEnd": 2, "weeks": [11], "roomIdI18n": "A101"},
                  {"dayOfWeek": 1, "timeStart": 1, "timeEnd": 2, "weeks": [1,2], "roomIdI18n": "A101"}
                ]
              }
            }
          ]
        }
      }
      ''';
      final result = parseCapturedTimetable(merged);
      expect(result!.courses.single.sessions.length, 1);
      expect(
        result.courses.single.sessions.single.weeks.weekNumbers,
        [1, 2, 10, 11],
      );
    });

    test('缺 weeks 数组时退化为全学期（1-16 周）', () {
      const noWeeks = '''
      {"data": {"selectedCourses": [{"course": {
        "courseName": "无周次课", "teachClassId": 2,
        "times": [{"dayOfWeek": 2, "timeStart": 3, "timeEnd": 4}]
      }}]}}
      ''';
      final s = parseCapturedTimetable(noWeeks)!.courses.single.sessions.single;
      expect(s.weeks, WeekPattern.range(1, 16));
    });
  });

  group('形状三：扁平 weekState 掩码', () {
    test('掩码 bit0 = 第 1 周；按教学班归组', () {
      const flat = '''
      [
        {"dayOfWeek": 1, "timeStart": 1, "timeEnd": 2, "weekState": 5,
         "teachingClassId": 42, "courseName": "掩码课", "courseCode": "MK001",
         "roomName": "B202", "teacherCodes": ["张老师"]},
        {"dayOfWeek": 3, "timeStart": 5, "timeEnd": 6, "weekState": 3,
         "teachingClassId": 42, "courseName": "掩码课", "courseCode": "MK001"}
      ]
      ''';
      final result = parseCapturedTimetable(flat);
      expect(result, isNotNull);
      expect(result!.courses.length, 1);
      final course = result.courses.single;
      expect(course.name, '掩码课');
      expect(course.teacher, '张老师');
      expect(course.sessions.length, 2);
      // weekState=5 → 第 1、3 周；3 → 第 1、2 周
      expect(course.sessions[0].weeks.weekNumbers, [1, 3]);
      expect(course.sessions[1].weeks.weekNumbers, [1, 2]);
    });

    test('dayOfWeek 越界的行被跳过', () {
      const bad = '''
      [{"dayOfWeek": 8, "timeStart": 1, "timeEnd": 2, "weekState": 1,
        "teachingClassId": 1, "courseName": "坏行"}]
      ''';
      expect(parseCapturedTimetable(bad)!.courses, isEmpty);
    });
  });

  group('探测与容错', () {
    test('looksLikeTimetable 识别三种形状', () {
      expect(looksLikeTimetable('{"data":{"selectedCourses":[]}}'), 0.98);
      expect(
        looksLikeTimetable('[{"weekState":1,"dayOfWeek":1}]'),
        greaterThanOrEqualTo(0.9),
      );
      expect(looksLikeTimetable('普通文本'), 0.0);
      expect(looksLikeTimetable('selectedCourses 但不是json'), 0.5);
    });

    test('非 JSON / 非课表返回 null', () {
      expect(parseCapturedTimetable('你好'), isNull);
      expect(parseCapturedTimetable('{"data":{"other":1}}'), isNull);
    });

    test('部分坏行不拖垮整体解析', () {
      const mixed = '''
      {"data": {"selectedCourses": [
        {"course": {"courseName": "好课", "teachClassId": 1,
          "times": [{"dayOfWeek": 1, "timeStart": 1, "timeEnd": 2, "weeks": [1]}]}},
        {"course": null},
        {"course": {"courseName": "坏时段", "teachClassId": 2, "times": [{"dayOfWeek": 9}]}}
      ]}}
      ''';
      final result = parseCapturedTimetable(mixed);
      expect(result!.courses.length, 1);
      expect(result.courses.single.name, '好课');
    });
  });
}
