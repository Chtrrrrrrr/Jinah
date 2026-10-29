/// 节次时间表：第 N 节上课的起止时刻（移植自 TJTimetable `TongjiTypes.kt`
/// 的 `TimetableDefaults.TONGJI_SLOTS`，2026-2027 学年第 1 学期校历）。
library;

class PeriodSlot {
  const PeriodSlot(this.index, this.begin, this.end);

  final int index;
  final String begin; // "HH:mm"
  final String end;
}

const tongjiSlots = [
  PeriodSlot(1, '08:00', '08:45'),
  PeriodSlot(2, '08:50', '09:35'),
  PeriodSlot(3, '10:00', '10:45'),
  PeriodSlot(4, '10:50', '11:35'),
  PeriodSlot(5, '13:30', '14:15'),
  PeriodSlot(6, '14:20', '15:05'),
  PeriodSlot(7, '15:30', '16:15'),
  PeriodSlot(8, '16:20', '17:05'),
  PeriodSlot(9, '18:30', '19:15'),
  PeriodSlot(10, '19:20', '20:05'),
  PeriodSlot(11, '20:10', '20:55'),
];

PeriodSlot? slotFor(int index) {
  for (final s in tongjiSlots) {
    if (s.index == index) return s;
  }
  return null;
}
