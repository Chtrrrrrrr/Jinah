import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'capture_parser.dart';
import 'timetable_import_service.dart';

/// 注入 1系统页面的 JS：包装 XHR 与 fetch，把响应经 JavascriptChannel 回传 Dart。
/// 只旁观、不主动发请求——课表接口的参数（studentCode 等）我们不逆向。
const _captureJs = '''
(function() {
  if (window.__jinahCaptureInstalled) return;
  window.__jinahCaptureInstalled = true;

  function report(url, body) {
    try {
      if (window.JinahCapture) {
        window.JinahCapture.postMessage(JSON.stringify({url: String(url), body: String(body)}));
      }
    } catch (e) {}
  }

  var origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.__jinahUrl = url;
    return origOpen.apply(this, arguments);
  };
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    this.addEventListener('load', function() {
      if (this.responseType === '' || this.responseType === 'text') {
        report(this.__jinahUrl, this.responseText);
      }
    });
    return origSend.apply(this, arguments);
  };

  var origFetch = window.fetch;
  window.fetch = function(url, opts) {
    return origFetch.apply(this, arguments).then(function(resp) {
      try {
        resp.clone().text().then(function(text) { report(url, text); });
      } catch (e) {}
      return resp;
    });
  };
})();
''';

/// 课表接口路径特征（移植自 TongjiWebCapture.kt，小写匹配）。
const _endpointFragments = [
  'findstudenttimetab',
  'findschooltimetab2',
  'getdatabk',
];

bool _isTimetableEndpoint(String? url) {
  if (url == null || url.isEmpty) return false;
  final lower = url.toLowerCase();
  return _endpointFragments.any(lower.contains);
}

bool _isTongjiUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'tongji.edu.cn' || host.endsWith('.tongji.edu.cn');
}

/// 链路 B：内置 WebView 登录 1系统，旁观捕获课表接口响应。
class WebViewCapturePage extends ConsumerStatefulWidget {
  const WebViewCapturePage({super.key});

  @override
  ConsumerState<WebViewCapturePage> createState() =>
      _WebViewCapturePageState();
}

class _WebViewCapturePageState extends ConsumerState<WebViewCapturePage> {
  late final WebViewController _controller;
  bool _importing = false;
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'JinahCapture',
        onMessageReceived: _onCaptureMessage,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _controller.runJavaScript(_captureJs),
        ),
      )
      ..loadRequest(Uri.parse('https://1.tongji.edu.cn'));
  }

  Future<void> _onCaptureMessage(JavaScriptMessage message) async {
    if (_importing || _captured) return;

    String? url;
    String? body;
    try {
      final decoded = jsonDecode(message.message);
      url = decoded['url'] as String?;
      body = decoded['body'] as String?;
    } catch (_) {
      return;
    }
    if (!_isTongjiUrl(url ?? '') || !_isTimetableEndpoint(url)) return;
    if (body == null || body.isEmpty) return;

    // 二次确认这确实是课表（响应里可能有同路径的非课表调用）
    if (looksLikeTimetable(body) < 0.9) return;

    setState(() => _importing = true);
    final data = parseCapturedTimetable(body);
    if (data == null || !mounted) {
      setState(() => _importing = false);
      return;
    }

    final result = await ref
        .read(timetableImportServiceProvider)
        .importCaptured(data, source: 'onetongji');
    if (!mounted) return;
    setState(() {
      _importing = false;
      _captured = result is ImportOk;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(result.describe())));
    if (result is ImportOk) {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;

    return Scaffold(
      appBar: AppBar(title: const Text('从 1系统 导入课表')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Text(
              '用统一身份认证登录后，在页面里点开「我的课表」。Jinah 会在后台识别课表数据并自动导入，全程不触碰你的密码。',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ),
          if (_importing)
            const LinearProgressIndicator(minHeight: 2)
          else
            const SizedBox(height: 2),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
