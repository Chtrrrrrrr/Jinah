import 'package:flutter_test/flutter_test.dart';
import 'package:jinah/features/timetable/domain/week_pattern.dart';

/// 移植自 TJTimetable `WeekPatternTest.kt` 的代表性用例。
void main() {
  group('教务系统真实形状', () {
    test('v2 逗号列表', () {
      final p = WeekPattern.parse('1,2,3,4,5');
      expect(p.weekNumbers, [1, 2, 3, 4, 5]);
      expect(p.firstWeek, 1);
      expect(p.lastWeek, 5);
      expect(p.isContiguous, isTrue);
    });

    test('weekNum 方括号区间', () {
      expect(WeekPattern.parse('[1-17]'), WeekPattern.range(1, 17));
    });

    test('第N-M周 / 第N至M周 / 各种破折号', () {
      expect(WeekPattern.parse('第1-17周'), WeekPattern.range(1, 17));
      expect(WeekPattern.parse('第1至17周'), WeekPattern.range(1, 17));
      expect(WeekPattern.parse('1~17'), WeekPattern.range(1, 17));
      expect(WeekPattern.parse('1～17'), WeekPattern.range(1, 17));
      expect(WeekPattern.parse('1—17'), WeekPattern.range(1, 17));
      expect(WeekPattern.parse('1–17'), WeekPattern.range(1, 17));
      expect(WeekPattern.parse('1−17'), WeekPattern.range(1, 17));
      expect(WeekPattern.parse('1－17'), WeekPattern.range(1, 17));
    });

    test('全角数字与全角逗号', () {
      expect(WeekPattern.parse('１，２，３').weekNumbers, [1, 2, 3]);
      expect(WeekPattern.parse('１－１７'), WeekPattern.range(1, 17));
    });

    test('CJK 分隔符', () {
      for (final s in ['1、2、3', '1；2；3', '1;2;3', '1/2/3', '1|2|3']) {
        expect(WeekPattern.parse(s).weekNumbers, [1, 2, 3], reason: s);
      }
    });

    test('容忍空白与制表符', () {
      expect(WeekPattern.parse(' 1 , 2 ,3 ').weekNumbers, [1, 2, 3]);
      expect(WeekPattern.parse('\t1,2,3\n').weekNumbers, [1, 2, 3]);
      expect(WeekPattern.parse(' [1-17] '), WeekPattern.range(1, 17));
    });
  });

  group('单双周', () {
    const oddWeeks = [1, 3, 5, 7, 9, 11, 13, 15, 17];

    test('奇数周各形状等价', () {
      for (final s in ['[1-17单]', '1-17(单)', '1-17单周', '奇数周1-17', '1-17单']) {
        expect(WeekPattern.parse(s).weekNumbers, oddWeeks, reason: s);
      }
      expect(WeekPattern.parse('[1-17单]').parityLabel, '单周');
      expect(WeekPattern.parse('[1-17单]').isOddOnly, isTrue);
    });

    test('偶数周各形状等价', () {
      const evenWeeks = [2, 4, 6, 8, 10, 12, 14, 16];
      for (final s in ['[2-16双]', '2-16双周', '2-16(双)', '偶数周2-16']) {
        expect(WeekPattern.parse(s).weekNumbers, evenWeeks, reason: s);
      }
      expect(WeekPattern.parse('[2-16双]').parityLabel, '双周');
    });

    test('单双混合按 token 各自解析，不互相覆盖', () {
      final p = WeekPattern.parse('1-8单,10-16双');
      expect(p.weekNumbers, [1, 3, 5, 7, 10, 12, 14, 16]);
      expect(p.parityLabel, isNull);
    });

    test('单标记不会越过逗号影响前面的 token', () {
      expect(
        WeekPattern.parse('1-8,10-16单').weekNumbers,
        [1, 2, 3, 4, 5, 6, 7, 8, 11, 13, 15],
      );
    });

    test('单周缩小到一周时失去徽标（设计如此）', () {
      final p = WeekPattern.parse('1-2单');
      expect(p.weekNumbers, [1]);
      expect(p.parityLabel, isNull);
    });
  });

  group('越界与畸形输入（永不抛异常）', () {
    test('区间截断到 64，单周忽略', () {
      expect(WeekPattern.parse('1-99'), WeekPattern.range(1, 64));
      expect(WeekPattern.parse('64').weekNumbers, [64]);
      expect(WeekPattern.parse('65').isEmpty, isTrue);
      expect(WeekPattern.parse('0').isEmpty, isTrue);
      expect(WeekPattern.parse('0-5').isEmpty, isTrue);
    });

    test('畸形区间为空', () {
      for (final s in ['5-3', '1-', '-5', '1-2-3']) {
        expect(WeekPattern.parse(s).isEmpty, isTrue, reason: s);
      }
    });

    test('垃圾输入为空模式', () {
      for (final s in ['abc', '周', '第周', '单', '双', '奇数', '偶数', '---', '，，', 'null']) {
        expect(WeekPattern.parse(s).isEmpty, isTrue, reason: s);
      }
      expect(WeekPattern.parse(null).isEmpty, isTrue);
      expect(WeekPattern.parse('   ').isEmpty, isTrue);
      expect(WeekPattern.parse('　').isEmpty, isTrue);
    });

    test('字母中夹数字提取数字（fail-open 设计）', () {
      expect(WeekPattern.parse('abc1def').weekNumbers, [1]);
    });
  });

  group('display 与 canonical', () {
    test('展示文本', () {
      expect(WeekPattern.empty.display(), '无');
      expect(WeekPattern.of([3]).display(), '第3周');
      expect(WeekPattern.range(1, 17).display(), '1-17周');
      expect(WeekPattern.parse('1-5,7-9').display(), '1-5,7-9周');
      expect(WeekPattern.parse('[1-17单]').display(), '1,3,5,7,9,11,13,15,17周(单)');
    });

    test('canonical 往返一致', () {
      final patterns = [
        WeekPattern.empty,
        WeekPattern.of([3]),
        WeekPattern.range(1, 17),
        WeekPattern.range(1, 64),
        WeekPattern.range(1, 5) + WeekPattern.of([7, 9]),
        WeekPattern.parse('[1-17单]'),
        WeekPattern.parse('[2-16双]'),
        WeekPattern.parse('1-99'),
        WeekPattern.parse('1-8，10-16'),
      ];
      for (final p in patterns) {
        expect(WeekPattern.parse(p.canonical()), p, reason: p.canonical());
      }
    });
  });

  group('集合运算', () {
    test('并交差', () {
      expect(
        (WeekPattern.range(1, 5) + WeekPattern.of([7, 9])).weekNumbers,
        [1, 2, 3, 4, 5, 7, 9],
      );
      expect(
        WeekPattern.range(1, 5).intersection(WeekPattern.range(3, 7)),
        WeekPattern.range(3, 5),
      );
      expect(
        WeekPattern.range(1, 5).difference(WeekPattern.of([3])),
        WeekPattern.of([1, 2, 4, 5]),
      );
    });

    test('ranges 连续段', () {
      expect(WeekPattern.parse('1-5,7-9').ranges(), [(1, 5), (7, 9)]);
      expect(
        (WeekPattern.range(1, 5) + WeekPattern.range(6, 10)).ranges(),
        [(1, 10)],
      );
    });
  });

  group('fromApiFields', () {
    test('优先已解析数组，其次 weekNum，再次 week', () {
      expect(
        WeekPattern.fromApiFields(weeks: [1, 3, 5], weekNum: '[1-17]', week: '2-16').weekNumbers,
        [1, 3, 5],
      );
      expect(
        WeekPattern.fromApiFields(weekNum: '[1-17]', week: '9'),
        WeekPattern.range(1, 17),
      );
      expect(
        WeekPattern.fromApiFields(weekNum: 'abc', week: '5-8'),
        WeekPattern.range(5, 8),
      );
      expect(WeekPattern.fromApiFields(weeks: [0, 99], weekNum: '[1-17单]').isOddOnly, isTrue);
      expect(WeekPattern.fromApiFields().isEmpty, isTrue);
    });
  });
}
