import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 用户自备凭据的本地存储（SPEC §4.6）。
///
/// 只进系统安全存储（Keychain/Keystore/Windows Credential Manager），
/// 不写日志、不随备份导出、永不打包进代码。
class SecretStore {
  SecretStore(this._storage);

  final FlutterSecureStorage _storage;

  static const _canvasToken = 'canvas_token';
  static const _openPlatformClientId = 'op_client_id';
  static const _openPlatformClientSecret = 'op_client_secret';
  static const _llmApiKey = 'llm_api_key';
  static const _llmBaseUrl = 'llm_base_url';
  static const _llmModel = 'llm_model';

  Future<String?> read(String key) => _storage.read(key: key);

  Future<void> write(String key, String? value) async {
    if (value == null || value.isEmpty) {
      await _storage.delete(key: key);
    } else {
      await _storage.write(key: key, value: value);
    }
  }

  Future<String?> get canvasToken => read(_canvasToken);
  Future<void> setCanvasToken(String? v) => write(_canvasToken, v);

  Future<String?> get openPlatformClientId => read(_openPlatformClientId);
  Future<void> setOpenPlatformClientId(String? v) =>
      write(_openPlatformClientId, v);

  Future<String?> get openPlatformClientSecret =>
      read(_openPlatformClientSecret);
  Future<void> setOpenPlatformClientSecret(String? v) =>
      write(_openPlatformClientSecret, v);

  Future<String?> get llmApiKey => read(_llmApiKey);
  Future<void> setLlmApiKey(String? v) => write(_llmApiKey, v);

  Future<String?> get llmBaseUrl => read(_llmBaseUrl);
  Future<void> setLlmBaseUrl(String? v) => write(_llmBaseUrl, v);

  Future<String?> get llmModel => read(_llmModel);
  Future<void> setLlmModel(String? v) => write(_llmModel, v);
}

final secretStoreProvider = Provider<SecretStore>(
  (ref) => SecretStore(const FlutterSecureStorage()),
);
