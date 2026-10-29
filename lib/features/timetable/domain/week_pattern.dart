/// 上课周集合：把同济教务系统各种形状的周字段统一成位掩码。
///
/// 移植自 TJTimetable 的 `domain/WeekPattern.kt`（同一作者，行为对齐其
/// `WeekPatternTest.kt` 全部用例）。核心语义：
///
/// - [parse] 永不抛异常：垃圾输入得到空模式，而不是弄砸整个导入
/// - 单/双是"修饰符"不是分隔符：`[1-17单]`、`1-17(单)`、`奇数周1-17` 同义
/// - 奇偶性按逗号 token 各自解析：`1-8单,10-16双` 不会互相覆盖
library;

class WeekPattern {
  const WeekPattern._(this.bits);

  /// 位掩码：bit 0 = 第 1 周。
  final int bits;

  static const int maxWeek = 64;

  static const int _oddMask = 0x5555555555555555;
  static const int _evenMask = ~_oddMask; // 双周位

  static const WeekPattern empty = WeekPattern._(0);

  // ---------------------------------------------------------- 基础属性

  bool get isEmpty => bits == 0;
  bool get isNotEmpty => bits != 0;

  /// 升序周号列表，如 `[1, 3, 5, 7]`。
  List<int> get weekNumbers {
    if (bits == 0) return const [];
    final out = <int>[];
    for (var w = 1; w <= maxWeek; w++) {
      if (bits & bit(w) != 0) out.add(w);
    }
    return out;
  }

  int get count => _popcount(bits);

  int? get firstWeek => isEmpty ? null : (bits & -bits).bitLength;
  int? get lastWeek => isEmpty ? null : bits.bitLength;

  bool contains(int week) => bits & bit(week) != 0;

  WeekPattern operator +(WeekPattern other) => WeekPattern._(bits | other.bits);
  WeekPattern intersection(WeekPattern other) => WeekPattern._(bits & other.bits);
  WeekPattern difference(WeekPattern other) => WeekPattern._(bits & ~other.bits);

  /// 限制在 `1..upTo` 周内的部分。
  WeekPattern limitedTo(int upTo) =>
      WeekPattern._(bits & _maskBelow(upTo));

  // ---------------------------------------------------------- 单双周

  /// 真正的单周（多于一周且全奇）。
  bool get isOddOnly => count > 1 && weekNumbers.every((w) => w % 2 == 1);

  /// 真正的双周（多于一周且全偶）。
  bool get isEvenOnly => count > 1 && weekNumbers.every((w) => w % 2 == 0);

  bool get isContiguous {
    if (isEmpty) return false;
    return count == lastWeek! - firstWeek! + 1;
  }

  /// "单周"/"双周" 徽标文案；非纯交替时为 null。
  String? get parityLabel => isOddOnly
      ? '单周'
      : isEvenOnly
          ? '双周'
          : null;

  // ---------------------------------------------------------- 展示

  /// 最大连续段，如 `[1..5, 7..9]`。
  List<(int, int)> ranges() {
    if (isEmpty) return const [];
    final out = <(int, int)>[];
    var start = -1;
    var prev = -1;
    for (var w = 1; w <= maxWeek; w++) {
      if (bits & bit(w) == 0) continue;
      if (start == -1) {
        start = w;
        prev = w;
        continue;
      }
      if (w == prev + 1) {
        prev = w;
        continue;
      }
      out.add((start, prev));
      start = w;
      prev = w;
    }
    if (start != -1) out.add((start, prev));
    return out;
  }

  /// 紧凑人类可读文本：`1-17周`、`1-17周(单)`、`1-5,7-9周`、`第3周`。
  String display() {
    if (isEmpty) return '无';
    final body = ranges().map((r) => r.$1 == r.$2 ? '${r.$1}' : '${r.$1}-${r.$2}').join(',');
    if (count == 1) return '第$firstWeek周';
    final suffix = isOddOnly ? '周(单)' : isEvenOnly ? '周(双)' : '周';
    return body + suffix;
  }

  /// 可再解析的持久化形式：`"1,3,5"`。
  String canonical() => weekNumbers.join(',');

  @override
  String toString() => display();

  @override
  bool operator ==(Object other) =>
      other is WeekPattern && other.bits == bits;

  @override
  int get hashCode => bits.hashCode;

  // ---------------------------------------------------------- 工厂

  static int bit(int week) =>
      (week >= 1 && week <= maxWeek) ? 1 << (week - 1) : 0;

  static int _maskBelow(int upTo) =>
      upTo <= 0 ? 0 : (upTo >= maxWeek ? -1 : (1 << upTo) - 1);

  factory WeekPattern.of(Iterable<int> weeks) {
    var bits = 0;
    for (final w in weeks) {
      bits |= bit(w);
    }
    return WeekPattern._(bits);
  }

  factory WeekPattern.fromBits(int bits) => WeekPattern._(bits);

  factory WeekPattern.range(int first, int last) =>
      first > last ? empty : WeekPattern.of(_inclRange(first, last));

  /// 解析同济教务系统（含网页复制粘贴）的所有周字段形状。永不抛异常。
  factory WeekPattern.parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return empty;
    final s = _normalize(raw);
    if (s.isEmpty) return empty;

    var bits = 0;
    for (final token in s.split(',')) {
      if (token.trim().isEmpty) continue;

      final wantsOdd = token.contains('单') || token.contains('奇数');
      final wantsEven = token.contains('双') || token.contains('偶数');

      // 只保留数字和短横线：顺带剥掉括号、"第/周"、单双标记本身
      final body = String.fromCharCodes(
        token.runes.where((r) => (r >= 0x30 && r <= 0x39) || r == 0x2D),
      );
      if (body.isEmpty) continue;

      var tokenBits = 0;
      final dash = body.indexOf('-');
      if (dash < 0) {
        final n = int.tryParse(body);
        if (n != null) tokenBits |= bit(n);
      } else {
        final lo = int.tryParse(body.substring(0, dash));
        final hi = int.tryParse(body.substring(dash + 1));
        // "5-3"、"0-5"、"1-2-3" 视为坏 token，只丢这一截
        if (lo != null && hi != null && lo >= 1 && hi >= lo) {
          final clamped = hi > maxWeek ? maxWeek : hi;
          for (var w = lo; w <= clamped; w++) {
            tokenBits |= bit(w);
          }
        }
      }

      tokenBits = switch ((wantsOdd, wantsEven)) {
        (true, false) => tokenBits & _oddMask,
        (false, true) => tokenBits & _evenMask,
        _ => tokenBits,
      };
      bits |= tokenBits;
    }
    return WeekPattern._(bits);
  }

  /// 合并 API 可能同时返回的多个周字段：优先已解析的数组，其次 weekNum 文本。
  factory WeekPattern.fromApiFields({
    List<int>? weeks,
    String? weekNum,
    String? week,
  }) {
    if (weeks != null && weeks.isNotEmpty) {
      final p = WeekPattern.of(weeks);
      if (p.isNotEmpty) return p;
    }
    final fromNum = WeekPattern.parse(weekNum);
    if (fromNum.isNotEmpty) return fromNum;
    return WeekPattern.parse(week);
  }

  /// 归一化全角字符、CJK 分隔符和各种破折号。
  static String _normalize(String raw) {
    final sb = StringBuffer();
    for (final ch in raw.runes) {
      var c = ch;
      switch (ch) {
        case 0xFF0C: // ，
        case 0x3001: // 、
        case 0xFF1B: // ；
        case 0x003B: // ;
        case 0x002F: // /
        case 0x007C: // |
          c = 0x2C; // ,
        case 0xFF5E: // ～
        case 0x007E: // ~
        case 0x2014: // —
        case 0x2013: // –
        case 0x2212: // −
        case 0xFF0D: // －
        case 0x30FC: // ー
        case 0x81F3: // 至
          c = 0x2D; // -
      }
      // ０-９ → 0-9
      if (c >= 0xFF10 && c <= 0xFF19) c = 0x30 + (c - 0xFF10);
      sb.writeCharCode(c);
    }
    return sb.toString();
  }

  static Iterable<int> _inclRange(int first, int last) sync* {
    for (var w = first; w <= last; w++) {
      yield w;
    }
  }

  static int _popcount(int v) {
    var count = 0;
    var x = v;
    while (x != 0) {
      x &= x - 1; // 清掉最低位的 1
      count++;
    }
    return count;
  }
}
