import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/database/database.dart';

/// 截止提醒（SPEC §4.4）：默认 D-1 20:00「明天截止」+ 当天 08:00「今天截止」两档。
///
/// Android 用系统本地通知（flutter_local_notifications，应用不开也响）；
/// 桌面端无系统级排程能力，本期只在应用打开时立即提示逾期待办（见 [notifyNow]）。
class ReminderService {
  ReminderService() {
    if (Platform.isAndroid || Platform.isIOS) {
      _plugin = FlutterLocalNotificationsPlugin();
    }
  }

  static const _channelId = 'deadlines';
  static const _channelName = '作业截止提醒';
  static const _channelDesc = '截止时间前一天 20:00 与当天 08:00 提醒';

  FlutterLocalNotificationsPlugin? _plugin;
  bool _initialized = false;

  bool get canSchedule => _plugin != null;

  Future<void> init() async {
    if (_plugin == null) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: android);
    await _plugin!.initialize(settings: initSettings);
    // Android 13+ 需要运行时通知权限
    await _plugin!
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// 全量重排：取消所有旧的，为每个未完成的带截止时间条目排两档提醒。
  Future<void> reschedule(List<TodoItem> openItems) async {
    if (!_initialized || _plugin == null) return;
    await _plugin!.cancelAll();

    for (final item in openItems) {
      final due = item.dueAt?.toLocal();
      if (due == null) continue;
      final base = item.id.hashCode & 0x3fffffff;

      // D-1 20:00
      final dayBefore = DateTime(due.year, due.month, due.day - 1, 20, 0);
      if (dayBefore.isAfter(DateTime.now())) {
        await _schedule(
          id: base * 2,
          at: dayBefore,
          title: '明天截止',
          body: item.title,
        );
      }

      // 当天 08:00
      final dayOf = DateTime(due.year, due.month, due.day, 8, 0);
      if (dayOf.isAfter(DateTime.now()) && !isSameMinute(dayOf, due)) {
        await _schedule(
          id: base * 2 + 1,
          at: dayOf,
          title: '今天截止',
          body: item.title,
        );
      }
    }
  }

  static bool isSameMinute(DateTime a, DateTime b) =>
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day &&
      a.hour == b.hour &&
      a.minute == b.minute;

  Future<void> _schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
  }) async {
    final tzAt = tz.TZDateTime(
      tz.local,
      at.year,
      at.month,
      at.day,
      at.hour,
      at.minute,
    );
    try {
      await _plugin!.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tzAt,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      // 单个条目排程失败不影响其余
    }
  }

  /// 桌面端/应用内即时提醒：现在就把逾期待办弹出来。
  Future<void> notifyNow(String title, String body) async {
    // 桌面端本地 toast 需要更重的集成，MVP 期先依赖应用内 UI（TODO 页已分区显示"已过期"）。
    // 此方法预留给后续 local_notifier 接入。
  }
}

final reminderServiceProvider = Provider<ReminderService>(
  (ref) => ReminderService(),
);
