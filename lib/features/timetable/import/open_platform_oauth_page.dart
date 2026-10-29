import 'dart:math';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'open_platform_api.dart';

/// 链路 A 第一步：内置 WebView 走统一身份认证，拦截 `jinah://oauth/callback`
/// 重定向拿到授权码。令牌换取与课表拉取由调用方继续。
class OpenPlatformOAuthPage extends StatefulWidget {
  const OpenPlatformOAuthPage({super.key, required this.clientId});

  final String clientId;

  @override
  State<OpenPlatformOAuthPage> createState() => _OpenPlatformOAuthPageState();
}

class _OpenPlatformOAuthPageState extends State<OpenPlatformOAuthPage> {
  late final WebViewController _controller;
  late final String _state;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _state = _randomState();
    final url = OpenPlatformApi.authorizationUrl(
      clientId: widget.clientId,
      state: _state,
    );
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _onNavigation),
      )
      ..loadRequest(url);
  }

  NavigationDecision _onNavigation(NavigationRequest request) {
    if (_done) return NavigationDecision.navigate;
    final uri = Uri.tryParse(request.url);
    if (uri != null && uri.scheme == 'jinah') {
      _done = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final code = uri.queryParameters['code'];
        final state = uri.queryParameters['state'];
        if (code == null || code.isEmpty) {
          final err = uri.queryParameters['error'] ?? '未知错误';
          Navigator.of(context).pop(OAuthError('授权失败：$err'));
          return;
        }
        if (state != _state) {
          Navigator.of(context)
              .pop(const OAuthError('state 校验失败，请重试'));
          return;
        }
        Navigator.of(context).pop(OAuthOk(code));
      });
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  static String _randomState() {
    final rng = Random.secure();
    return List.generate(16, (_) => rng.nextInt(16).toRadixString(16)).join();
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Scaffold(
      appBar: AppBar(title: const Text('统一身份认证登录')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Text(
              '登录同济大学统一身份认证。授权后页面会自动关闭，Jinah 只保存访问令牌（2 小时有效），不保存你的密码。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}

sealed class OAuthResult {
  const OAuthResult();

  String? get code => switch (this) {
        OAuthOk(:final c) => c,
        OAuthError() => null,
      };

  String describe() => switch (this) {
        OAuthOk() => '授权成功',
        OAuthError(:final message) => message,
      };
}

class OAuthOk extends OAuthResult {
  const OAuthOk(this.c);

  final String c;
}

class OAuthError extends OAuthResult {
  const OAuthError(this.message);

  final String message;
}
