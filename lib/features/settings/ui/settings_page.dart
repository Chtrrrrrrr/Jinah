import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/secrets/secret_store.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/backup/backup_service.dart';

/// 设置：外观（主题/强调色）+ 凭据管理 + 关于。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('设置', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 24),
          _SectionHeader('外观'),
          Row(
            children: [
              SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.dark,
                    label: Text('深色'),
                    icon: Icon(Icons.dark_mode, size: 16),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    label: Text('浅色'),
                    icon: Icon(Icons.light_mode, size: 16),
                  ),
                ],
                selected: {settings.themeMode},
                onSelectionChanged: (v) => ref
                    .read(settingsControllerProvider.notifier)
                    .setThemeMode(v.first),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: [
              for (final c in _accentPresets)
                _AccentDot(
                  color: c,
                  selected: settings.accent.toARGB32() == c.toARGB32(),
                  onTap: () => ref
                      .read(settingsControllerProvider.notifier)
                      .setAccent(c),
                ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader('凭据（仅存储在本机）'),
          const _CredentialTile(
            title: 'Canvas Token',
            subtitle: 'canvas.tongji.edu.cn → 设置 → 生成令牌',
            getter: _canvasGetter,
            setter: _canvasSetter,
          ),
          const _CredentialTile(
            title: '开放平台 Client ID',
            subtitle: 'api.tongji.edu.cn 申请获得',
            getter: _clientIdGetter,
            setter: _clientIdSetter,
          ),
          const _CredentialTile(
            title: 'LLM API Key',
            subtitle: 'OpenAI 兼容接口，用于作业解析',
            getter: _llmKeyGetter,
            setter: _llmKeySetter,
          ),
          const _CredentialTile(
            title: 'LLM Base URL',
            subtitle: '可选，默认 OpenAI 官方地址',
            getter: _llmBaseGetter,
            setter: _llmBaseSetter,
          ),
          const _CredentialTile(
            title: 'LLM 模型',
            subtitle: '可选，默认 gpt-4o-mini（DeepSeek 填 deepseek-chat）',
            getter: _llmModelGetter,
            setter: _llmModelSetter,
          ),
          const SizedBox(height: 24),
          const _SectionHeader('数据'),
          Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: () async {
                  final r = await ref
                      .read(backupServiceProvider)
                      .exportToFile();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(r.describe())),
                    );
                  }
                },
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: const Text('导出备份'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final r = await ref
                      .read(backupServiceProvider)
                      .importFromFile();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(r.describe())),
                    );
                  }
                },
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('导入备份'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionHeader('关于'),
          const ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text('Jinah 0.1.0'),
            subtitle: Text('同济大学学生 AI 助手 · 开源 · 无服务器'),
          ),
        ],
      ),
    );
  }
}

const _accentPresets = [
  Color(0xFF7F6DF2), // Obsidian 紫
  Color(0xFFE8590C), // 橙
  Color(0xFF2F9E44), // 绿
  Color(0xFF1971C2), // 蓝
  Color(0xFFE64980), // 粉
  Color(0xFFF08C00), // 琥珀
];

Future<String?> _canvasGetter(SecretStore s) => s.canvasToken;
Future<void> _canvasSetter(SecretStore s, String? v) => s.setCanvasToken(v);
Future<String?> _clientIdGetter(SecretStore s) => s.openPlatformClientId;
Future<void> _clientIdSetter(SecretStore s, String? v) =>
    s.setOpenPlatformClientId(v);
Future<String?> _llmKeyGetter(SecretStore s) => s.llmApiKey;
Future<void> _llmKeySetter(SecretStore s, String? v) => s.setLlmApiKey(v);
Future<String?> _llmBaseGetter(SecretStore s) => s.llmBaseUrl;
Future<void> _llmBaseSetter(SecretStore s, String? v) => s.setLlmBaseUrl(v);
Future<String?> _llmModelGetter(SecretStore s) => s.llmModel;
Future<void> _llmModelSetter(SecretStore s, String? v) => s.setLlmModel(v);

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          color: muted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AccentDot extends StatelessWidget {
  const _AccentDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}

class _CredentialTile extends ConsumerStatefulWidget {
  const _CredentialTile({
    required this.title,
    required this.subtitle,
    required this.getter,
    required this.setter,
  });

  final String title;
  final String subtitle;
  final Future<String?> Function(SecretStore) getter;
  final Future<void> Function(SecretStore, String?) setter;

  @override
  ConsumerState<_CredentialTile> createState() => _CredentialTileState();
}

class _CredentialTileState extends ConsumerState<_CredentialTile> {
  final _controller = TextEditingController();
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ref.read(secretStoreProvider);
    final value = await widget.getter(store);
    if (mounted) {
      _controller.text = value ?? '';
      setState(() => _loaded = true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = ref.read(secretStoreProvider);
    await widget.setter(store, _controller.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${widget.title} 已保存')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: true,
                enabled: _loaded,
                decoration: InputDecoration(
                  labelText: widget.title,
                  helperText: widget.subtitle,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: '保存',
              icon: const Icon(Icons.save_outlined),
              onPressed: _loaded ? _save : null,
            ),
          ],
        ),
      ],
    );
  }
}
