import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/secrets/secret_store.dart';
import 'capture_parser.dart';
import 'open_platform_api.dart';
import 'open_platform_oauth_page.dart';
import 'timetable_import_service.dart';

class OpenPlatformImportService {
  OpenPlatformImportService(this._secrets, this._api, this._importer);

  final SecretStore _secrets;
  final OpenPlatformApi _api;
  final TimetableImportService _importer;

  bool _tokenFresh(String? token, int expiresAt) =>
      token != null && token.isNotEmpty && _secrets.isOpTokenFresh(expiresAt);

  Future<bool> get hasFreshToken async => _tokenFresh(
        await _secrets.opToken,
        await _secrets.opTokenExpiresAt,
      );

  /// 令牌还有效：直接拉课表导入。
  Future<TimetableImportResult> importWithFreshToken() async {
    final token = await _secrets.opToken;
    final expiresAt = await _secrets.opTokenExpiresAt;
    if (!_tokenFresh(token, expiresAt)) {
      return const ImportFailure('令牌已过期，请重新授权');
    }
    return await _import(token!);
  }

  /// OAuth 回来的授权码：换令牌 → 存 → 拉课表导入。
  Future<TimetableImportResult> importWithCode(String code) async {
    try {
      final clientId = await _secrets.openPlatformClientId;
      if (clientId == null || clientId.isEmpty) {
        return const ImportFailure('未配置开放平台 Client ID（设置 → 凭据）');
      }
      final exchanged = await _api.exchangeCode(
        clientId: clientId,
        clientSecret: await _secrets.openPlatformClientSecret,
        code: code,
      );
      await _secrets.setOpToken(exchanged.token);
      await _secrets.setOpTokenExpiresAt(exchanged.expiresAt);
      return await _import(exchanged.token);
    } on OpenPlatformException catch (e) {
      return ImportFailure(e.message);
    }
  }

  Future<TimetableImportResult> _import(String token) async {
    try {
      var userId = await _secrets.opUserId;
      userId ??= await _api.fetchUserId(token);
      await _secrets.setOpUserId(userId);

      final term = await _api.fetchCurrentTerm(token);
      var data = await _api.fetchStudentTimetable(
        token,
        userId,
        calendarId: term.calendarId,
      );
      // 课表 DTO 不带 calendarId，从学期接口补上
      data = ImportedTimetable(
        calendarId: term.calendarId,
        calendarName: term.name,
        courses: data.courses,
      );
      return await _importer.importCaptured(data, source: 'openplatform');
    } on OpenPlatformException catch (e) {
      return ImportFailure(e.message);
    }
  }
}

final openPlatformImportServiceProvider =
    Provider<OpenPlatformImportService>(
  (ref) => OpenPlatformImportService(
    ref.watch(secretStoreProvider),
    ref.watch(openPlatformApiProvider),
    ref.watch(timetableImportServiceProvider),
  ),
);

/// UI 入口：判断令牌状态 → 需要则先走 OAuth 授权 → 导入 → SnackBar 反馈。
Future<void> runOpenPlatformImportFlow(
  BuildContext context,
  WidgetRef ref,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final secrets = ref.read(secretStoreProvider);
  final clientId = await secrets.openPlatformClientId;
  if (clientId == null || clientId.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('先在 设置 → 凭据 填写开放平台 Client ID')),
    );
    return;
  }

  final service = ref.read(openPlatformImportServiceProvider);
  if (!await service.hasFreshToken) {
    if (!context.mounted) return;
    final result = await Navigator.of(context).push<OAuthResult>(
      MaterialPageRoute(
        builder: (_) => OpenPlatformOAuthPage(clientId: clientId),
      ),
    );
    if (result is OAuthError && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(result.message)));
      return;
    }
    if (result is! OAuthOk || !context.mounted) return;
    messenger.showSnackBar(
      const SnackBar(content: Text('授权成功，正在导入课表…')),
    );
    final r = await service.importWithCode(result.code!);
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(r.describe())));
    }
    return;
  }

  messenger.showSnackBar(
    const SnackBar(content: Text('正在同步开放平台课表…')),
  );
  final r = await service.importWithFreshToken();
  if (context.mounted) {
    messenger.showSnackBar(SnackBar(content: Text(r.describe())));
  }
}
