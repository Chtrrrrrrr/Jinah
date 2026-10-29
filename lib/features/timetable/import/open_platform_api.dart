import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/term_calendar.dart';

/// 同济大学开放平台客户端（api.tongji.edu.cn）。
///
/// - 学年学期接口**免 token**——用来给捕获到的 calendarId 补开学日期
///   （TJTimetable 只能内置学期快照，这里用公开接口实时查，是改进）
/// - 课表接口需要用户自备 client_id 走 OAuth2（授权码模式）
class OpenPlatformApi {
  OpenPlatformApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
            ));

  final Dio _dio;

  static const baseUrl = 'https://api.tongji.edu.cn';
  static const authPath =
      'keycloak/realms/OpenPlatform/protocol/openid-connect/auth';
  static const idpHint = 'tjiam';

  /// 课表 scope 必须显式点名（平台按接口授权）。
  static const timetableScope =
      'openid v1_rt_onetongji_student_timetable '
      'v1_rt_onetongji_school_calendar_current_term_calendar';

  static const oauthRedirect = 'jinah://oauth/callback';

  /// 授权码模式的授权 URL（在内置 WebView 中打开，拦截重定向拿 code）。
  static Uri authorizationUrl({
    required String clientId,
    String redirectUri = oauthRedirect,
    required String state,
  }) =>
      Uri.https('api.tongji.edu.cn', authPath, {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': timetableScope,
        'state': state,
        'kc_idp_hint': idpHint, // 必须带：选择同济统一身份认证，否则跳错登录页
      });

  /// 学年学期信息（免授权）。返回按时间倒序的原始条目。
  Future<List<Map<String, dynamic>>> fetchSemesters() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/rt/teaching_info/semester',
      options: Options(validateStatus: (c) => c != null && c < 500),
    );
    if (res.statusCode != 200) {
      throw OpenPlatformException('学期接口错误：HTTP ${res.statusCode}');
    }
    final data = res.data?['data'];
    if (data is! List) return const [];
    return data.whereType<Map<String, dynamic>>().toList();
  }

  /// 用 calendarId 在学期列表里找开学日期，构造学期日历；找不到返回 null。
  Future<TermCalendar?> termCalendarFor(String calendarId) async {
    final semesters = await fetchSemesters();
    for (final s in semesters) {
      if (s['ID']?.toString() != calendarId) continue;
      final begin = _parseDate(s['beginDay']?.toString());
      if (begin == null) return null;
      final end =
          _parseDate(s['endDay']?.toString()) ??
              begin.add(const Duration(days: 16 * 7 - 1));
      final name = s['semesterName']?.toString() ?? '未知学期';
      return TermCalendar.fromApi(
        calendarId: calendarId,
        name: name,
        year: int.tryParse(s['year']?.toString() ?? '') ?? begin.year,
        term: int.tryParse(s['semester']?.toString() ?? '') ?? 1,
        beginDay: begin,
        endDay: end,
        totalWeeks: 16,
        isCurrent: true,
      );
    }
    return null;
  }

  DateTime? _parseDate(String? raw) {
    if (raw == null || raw.length < 10) return null;
    return DateTime.tryParse(raw.substring(0, 10));
  }
}

class OpenPlatformException implements Exception {
  OpenPlatformException(this.message);

  final String message;

  @override
  String toString() => message;
}

final openPlatformApiProvider = Provider<OpenPlatformApi>(
  (ref) => OpenPlatformApi(),
);
