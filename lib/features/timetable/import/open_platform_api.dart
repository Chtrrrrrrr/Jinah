import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/term_calendar.dart';
import '../domain/week_pattern.dart';
import 'capture_parser.dart';

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

  // ------------------------------------------------------------ OAuth 令牌

  /// 授权码换令牌（SPEC §4.1；client_secret 仅客户端模式必需，有则带上）。
  Future<({String token, int expiresAt})> exchangeCode({
    required String clientId,
    required String code,
    String? clientSecret,
    String redirectUri = oauthRedirect,
  }) async {
    final form = {
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirectUri,
      if (clientSecret != null && clientSecret.isNotEmpty)
        'client_secret': clientSecret,
    };
    final res = await _dio.post<Map<String, dynamic>>(
      '/v1/token',
      data: FormData.fromMap(form),
      options: Options(validateStatus: (c) => c != null && c < 500),
    );
    if (res.statusCode != 200 || res.data?['access_token'] is! String) {
      throw OpenPlatformException('换取令牌失败：HTTP ${res.statusCode}');
    }
    final expiresIn = (res.data!['expires_in'] as num?)?.toInt() ?? 7200;
    final expiresAt =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 + expiresIn;
    return (token: res.data!['access_token'] as String, expiresAt: expiresAt);
  }

  /// Keycloak userinfo → 学号（preferred_username）。
  Future<String> fetchUserId(String token) async {
    final res = await _dio.get<Map<String, dynamic>>(
      'keycloak/realms/OpenPlatform/protocol/openid-connect/userinfo',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (c) => c != null && c < 500,
      ),
    );
    final id = res.data?['preferred_username'];
    if (res.statusCode != 200 || id is! String || id.isEmpty) {
      throw OpenPlatformException('获取学号失败：HTTP ${res.statusCode}');
    }
    return id;
  }

  // ------------------------------------------------------------ 课表（需授权）

  /// 当前学期日历（calendarId + 起止，epoch 毫秒）。
  Future<TermCalendar> fetchCurrentTerm(String token) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/rt/onetongji/school_calendar_current_term_calendar',
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (c) => c != null && c < 500,
      ),
    );
    final sc = res.data?['data']?['schoolCalendar'];
    if (res.statusCode != 200 || sc is! Map) {
      throw OpenPlatformException('获取当前学期失败：HTTP ${res.statusCode}');
    }
    final beginMs = (sc['beginDay'] as num?)?.toInt();
    final endMs = (sc['endDay'] as num?)?.toInt();
    if (beginMs == null) {
      throw const OpenPlatformException('学期数据缺少 beginDay');
    }
    final begin = DateTime.fromMillisecondsSinceEpoch(beginMs, isUtc: true)
        .add(const Duration(hours: 8)); // 学校按北京时间午夜记录
    final end = endMs != null
        ? DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true)
            .add(const Duration(hours: 8))
        : begin.add(const Duration(days: 16 * 7 - 1));
    return TermCalendar.fromApi(
      calendarId: sc['id']?.toString() ?? 'current',
      name: res.data!['data']?['simpleName']?.toString() ?? '当前学期',
      year: (sc['year'] as num?)?.toInt() ?? begin.year,
      term: (sc['term'] as num?)?.toInt() ?? 1,
      beginDay: DateTime(begin.year, begin.month, begin.day),
      endDay: DateTime(end.year, end.month, end.day),
      totalWeeks: (sc['weekNum'] as num?)?.toInt() ?? 16,
      isCurrent: true,
    );
  }

  /// 学生课表（实时端点，一条课程嵌套 timeTableList，单双周可恢复）。
  Future<ImportedTimetable> fetchStudentTimetable(
    String token,
    String userId, {
    String? calendarId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/v1/rt/onetongji/student_timetable',
      queryParameters: {
        'userId': userId,
        'calendarId': ?calendarId,
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        validateStatus: (c) => c != null && c < 500,
      ),
    );
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const OpenPlatformException('令牌失效或无课表接口权限（scope 未授权）');
    }
    if (res.statusCode != 200) {
      throw OpenPlatformException('获取课表失败：HTTP ${res.statusCode}');
    }
    final data = res.data?['data'];
    if (data is! List) return ImportedTimetable();

    final courses = <ImportedCourse>[];
    for (final item in data) {
      if (item is! Map) continue;
      final times = item['timeTableList'];
      if (times is! List) continue;

      final sessions = <ImportedSession>[];
      for (final t in times) {
        if (t is! Map) continue;
        final day = (t['dayOfWeek'] as num?)?.toInt();
        final start = (t['timeStart'] as num?)?.toInt();
        final end = (t['timeEnd'] as num?)?.toInt();
        if (day == null || start == null || end == null) continue;
        if (day < 1 || day > 7) continue;

        final weeks = WeekPattern.fromApiFields(
          weeks: t['weeks'] is List
              ? (t['weeks'] as List)
                  .map((e) => (e as num?)?.toInt() ?? 0)
                  .toList()
              : null,
          weekNum: t['weekNum']?.toString() ?? t['weekstr']?.toString(),
        );
        if (weeks.isEmpty) continue;

        sessions.add(ImportedSession(
          day: day,
          startPeriod: start,
          endPeriod: end,
          weeks: weeks,
          room: t['roomIdI18n']?.toString().isNotEmpty == true
              ? t['roomIdI18n'].toString()
              : (t['classRoomName']?.toString()),
        ));
      }
      if (sessions.isEmpty) continue;

      final id = item['teachingClassId']?.toString() ??
          item['classCode']?.toString() ??
          item['courseCode']?.toString();
      if (id == null) continue;

      courses.add(ImportedCourse(
        id: id,
        name: item['courseName']?.toString() ?? '(未知课程)',
        courseCode: item['courseCode']?.toString(),
        teachingClassCode: item['classCode']?.toString(),
        teacher: item['teacherName']?.toString(),
        campus: item['campus']?.toString(),
        sessions: sessions,
      ));
    }

    courses.sort((a, b) => a.name.compareTo(b.name));
    return ImportedTimetable(courses: courses);
  }
}

class OpenPlatformException implements Exception {
  const OpenPlatformException(this.message);

  final String message;

  @override
  String toString() => message;
}

final openPlatformApiProvider = Provider<OpenPlatformApi>(
  (ref) => OpenPlatformApi(),
);
