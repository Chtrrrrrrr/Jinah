# Jinah

同济大学学生 AI 助手 · 开源 · 无账号、无服务器

把分散在 Canvas、1系统、微信群里的作业通知汇总成一张清晰的 TODO 清单，用 AI 把非结构化通知解析成结构化任务。设计基准见 [SPEC.md](SPEC.md)。

## 状态

✅ 一期功能齐备（待真机验证）：课表双链路导入 + TODO 与截止提醒 + Canvas 作业同步 + AI 解析（文本/截图）+ JSON 备份 + ICS 导出。真机相关的链路（WebView 登录、系统通知、文件选择器）需装机验证。

## 核心原则

1. **开源、无账号、无服务器**——数据只存在你自己的设备上
2. **凭据用户自备**——Canvas token、开放平台 client_id、LLM API key 均由你自己提供，只存本地（系统安全存储），绝不打包进代码
3. **AI 只做解析与规划**——能规则化的不丢给 AI
4. **本地优先**——核心功能离线可用

## 界面

Obsidian 设计语言：默认深色、紫色强调色可自定义、`Ctrl/Cmd+K` 命令面板。

## 开发

需要 Flutter stable（`flutter doctor` 自检）。本机 SDK 已装在 `C:\dev\flutter`（未加入全局 PATH，用时把 `C:\dev\flutter\bin` 加入 PATH，或直接调 `C:\dev\flutter\bin\flutter.bat`）。

```bash
flutter pub get
flutter run            # 需先装 Android SDK（Android Studio）或 Windows 桌面工具链
flutter test
flutter analyze
```

国内网络可配置镜像：

```bash
export PUB_HOSTED_URL=https://pub.flutter-io.cn
export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

Windows 本机构建需在系统设置中开启**开发者模式**（允许创建符号链接，插件机制依赖它）。Android 构建需安装 Android Studio（SDK + 许可），Windows 桌面构建需 Visual Studio 的 C++ 桌面开发工作负载。

## 构建

```bash
flutter build apk --release     # Android
flutter build windows --release # Windows 桌面（需 Visual Studio C++ 工作负载）
```

CI 在每次推送时自动构建 APK 与 Windows 安装包（见 `.github/workflows/ci.yml`）。

## 许可证

待定（MIT 或 AGPL，见 SPEC §7）。
