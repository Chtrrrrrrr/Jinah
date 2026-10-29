import 'package:dio/dio.dart';

/// OpenAI 兼容的 chat/completions 客户端（用户自备 key，客户端直连）。
class LlmClient {
  LlmClient({
    required this.apiKey,
    this.baseUrl,
    this.model,
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
              ),
            );

  final String apiKey;
  final String? baseUrl;
  final String? model;
  final Dio _dio;

  static const defaultBaseUrl = 'https://api.openai.com/v1';
  static const defaultModel = 'gpt-4o-mini';

  String get _base =>
      (baseUrl == null || baseUrl!.isEmpty) ? defaultBaseUrl : baseUrl!;

  String get _model =>
      (model == null || model!.isEmpty) ? defaultModel : model!;

  /// 调用 chat completions，返回 message.content 原文。
  Future<String> chat({
    required String systemPrompt,
    required String userPrompt,
  }) async {
    final base = _base.replaceAll(RegExp(r'/+$'), '');
    final res = await _dio.post<Map<String, dynamic>>(
      '$base/chat/completions',
      options: Options(
        headers: {'Authorization': 'Bearer $apiKey'},
        validateStatus: (code) => code != null && code < 500,
      ),
      data: {
        'model': _model,
        'temperature': 0,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
      },
    );

    if (res.statusCode == 401) {
      throw const LlmException('LLM API Key 无效或已过期');
    }
    if (res.statusCode != 200) {
      throw LlmException('LLM 接口错误：HTTP ${res.statusCode}');
    }
    final choices = res.data?['choices'];
    final content = choices is List && choices.isNotEmpty
        ? (choices.first as Map?)?['message']?['content']
        : null;
    if (content is! String || content.isEmpty) {
      throw const LlmException('LLM 响应格式异常');
    }
    return content;
  }
}

class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => message;
}
