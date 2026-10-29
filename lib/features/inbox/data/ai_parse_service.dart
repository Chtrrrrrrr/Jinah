import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ai/llm_client.dart';
import '../../../core/ai/task_parser.dart';
import '../../../core/secrets/secret_store.dart';

sealed class AiParseResult {
  const AiParseResult();
}

class AiNeedsKey extends AiParseResult {
  const AiNeedsKey();
}

class AiParseOk extends AiParseResult {
  const AiParseOk(this.tasks);

  final List<ParsedTask> tasks;
}

class AiParseFailure extends AiParseResult {
  const AiParseFailure(this.message);

  final String message;
}

/// 收件箱 AI 解析服务：SecretStore 读 key → LLM 调用 → 校验。
class AiParseService {
  AiParseService(this._secrets);

  final SecretStore _secrets;

  Future<AiParseResult> parse(String rawText) async {
    final key = await _secrets.llmApiKey;
    if (key == null || key.isEmpty) {
      return const AiNeedsKey();
    }

    try {
      final client = LlmClient(
        apiKey: key,
        baseUrl: await _secrets.llmBaseUrl,
        model: await _secrets.llmModel,
      );
      final output = await client.chat(
        systemPrompt: buildSystemPrompt(),
        userPrompt: buildUserPrompt(rawText: rawText, now: DateTime.now()),
      );
      return AiParseOk(parseTasks(output));
    } on LlmException catch (e) {
      return AiParseFailure(e.message);
    } on TaskParseException catch (e) {
      return AiParseFailure('AI 解析失败：${e.message}');
    } on DioException catch (e) {
      return AiParseFailure('网络错误：${e.message ?? e.type.name}');
    }
  }
}

final aiParseServiceProvider = Provider<AiParseService>(
  (ref) => AiParseService(ref.watch(secretStoreProvider)),
);
