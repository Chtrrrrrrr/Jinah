/// 作业/课表来源适配器协议（SPEC §4.2）。
///
/// 每个来源实现统一接口，新增来源 = 新增适配器，不动主流程。
library;

/// 未解析的中间形态：来源抓到的原始条目。
class RawItem {
  RawItem({
    required this.sourceRef,
    required this.title,
    this.courseHint,
    this.rawText = '',
    this.dueAtHint,
  });

  /// 来源内唯一标识，去重键。
  final String sourceRef;

  /// 课程名线索（可能为空，交给 AI 或匹配逻辑）。
  final String? courseHint;

  final String title;

  /// 富文本原文（进 AI 解析管线）。
  final String rawText;

  /// 源里已有的时间线索（Canvas 有精确值，通知可能没有）。
  final DateTime? dueAtHint;
}

enum AuthRequirement { none, token, oauth, webviewLogin }

abstract class SourceAdapter {
  String get sourceId;
  String get displayName;
  AuthRequirement get auth;

  /// 拉取原始条目。凭据缺失时应抛 [SourceAuthException]。
  Future<List<RawItem>> fetch();
}

class SourceAuthException implements Exception {
  SourceAuthException(this.message);

  final String message;

  @override
  String toString() => 'SourceAuthException: $message';
}
