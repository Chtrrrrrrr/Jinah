# Jinah 设计文档（SPEC）

> 同济大学学生 AI 助手 · 开源项目 · 本文档是开发基准，改动设计需更新本文档。

## 1. 产品定位与原则

**Jinah** 是面向同济学生的开源学习助手：把分散在各平台的课程表和作业通知汇总成一张清晰的 TODO 清单，并用 AI 把非结构化通知解析成结构化任务。

不可动摇的原则（所有技术决策的裁判）：

1. **开源、无账号、无服务器**。零持续成本，隐私天然合规（数据只存在用户设备）。
2. **凭据用户自备**：Canvas token、开放平台 client_id/secret、LLM API key 均由用户自己提供，只存本地，绝不进日志、绝不打包进代码（APK/代码里的 secret 就是公开的）。
3. **AI 只做结构化解析和规划，不做对话**。能规则化的不丢给 AI（如物理实验报告：做完实验 → N 天内交报告，是确定性规则）。
4. **本地优先**：核心功能离线可用；同步是锦上添花，不是前提。

## 2. 一期范围（MVP）

**做：**

- **课表**：双链路导入（见 §4.1），周数/调休解析，ICS 导出，截图 AI 识别兜底
- **作业·Canvas**：用户自生成 token → Canvas REST API 自动同步作业（含截止时间）到 TODO
- **作业·1系统**：WebView 捕获首页课程通知 → AI 解析 → TODO
- **作业·兜底**：复制/粘贴/截图转发 + AI 解析（覆盖微信群/QQ群/口头布置）
- **TODO**：本地数据库，截止前本地通知提醒，导出/导入 JSON 备份
- **平台**：Android（手机/平板）+ Windows/macOS/Linux 桌面，GitHub Releases 分发

**不做（二期+）：**

- 物理实验报告规则引擎（自动加报告 TODO）
- 日程规划 / deadline 撞车检测（功能已获认可，二期做厚）
- WebDAV 自动同步（一期只有手动导出/导入）
- 1系统通知改走开放平台 `msg_list` 接口（先申请 client+scope，批下来切换）
- 微信/QQ 群自动读取（不可行，永远是"转发进来+AI解析"）

## 3. 架构总览

```
┌────────────────────────── Flutter 客户端 ──────────────────────────┐
│                                                                    │
│  UI 层        课表视图 │ TODO 列表 │ 通知解析收件箱 │ 设置/凭据管理    │
│  状态层       （建议 Riverpod，见 §7 待定项）                        │
│  领域层        WeekPattern/TermCalendar/调休解析/Todo 规则           │
│  采集适配器    ┌──────────┬──────────────┬─────────────┐           │
│               │ CanvasApi │ OneTongjiApi │ WebView捕获 │  手动/分享  │
│               └──────────┴──────────────┴─────────────┘           │
│  存储层        Drift (SQLite) │ flutter_secure_storage (凭据)        │
│  AI 管线       客户端直连 LLM API（用户 key），纯函数解析器            │
└────────────────────────────────────────────────────────────────────┘
            │                │                  │
   canvas.tongji.edu.cn  api.tongji.edu.cn  1.tongji.edu.cn
   (官方 REST, token)     (开放平台 OAuth2)   (WebView 旁观捕获)
```

- 没有后端。三个采集源全部客户端直连，各自独立可替换。
- **适配器协议**是架构核心：每个作业/课表来源实现统一接口，新增来源 = 新增适配器，不动主流程。

## 4. 模块设计

### 4.1 课表

移植 [TJTimetable](https://github.com/chtrrrrrrr/TJTimetable)（本项目作者的前作，Kotlin）的两条链路，领域逻辑平移到 Dart：

**链路 A：开放平台 OAuth2**（`api.tongji.edu.cn`，官方 REST）

- 授权码模式：只需 client_id（用户自备），系统浏览器/内置 WebView 走统一身份认证（Keycloak），`kc_idp_hint=tjiam` 必须带。
- 客户端模式：client_id + client_secret 均用户自备，设置页填写。
- Token 有效期 7200s，请求前检查过期（60s 偏移）。
- 关键端点：
  - `GET /v1/rt/onetongji/student_timetable?userId=&calendarId=`（实时，含解析好的周数数组，主源）
  - `GET /v2/dc/teaching_info/student_timetable`（批量，sinceId 游标分页，兜底）
  - `GET /v1/rt/teaching_info/semester`（**免 token**）
  - `GET /v1/rt/onetongji/calendar`（校历：节假日/调休/寒暑假，**免 token**）
- 待移植参考：`TongjiApi.kt`、`TongjiDtos.kt`、`TongjiImport.kt`、`CredentialsStore.kt`。

**链路 B：1系统 WebView 旁观捕获**（零注册依赖，主链路）

- 内置 WebView 登录 `1.tongji.edu.cn`，用户点开"我的课表"，页面自己发请求，我们拦截响应接数据。
- 捕获目标（路径特征，小写匹配）：`findStudentTimetab`（本科）、`findSchoolTimetab2`（研究生）、`getDataBk`（选课服务，calendarId 在响应体）。
- `calendarId` 从 URL 查询参数接。
- **不逆向 `studentCode` 加密**（算法在前端 bundle 里、随发版变），只当旁观者。
- Cookie 只进内存拼请求头，**不落盘不落日志**。
- 待移植参考：`TongjiWebCapture.kt`、`TongjiLoginScreen.kt`、`TongjiStudentAdapter.kt`、`TongjiResponseProbe.kt`、`TongjiTerms.kt`。

**领域逻辑**（纯函数，Dart 移植 + 单测照抄）：`WeekPattern`（"1-8周,单周"类文本↔周集合）、`TermCalendar`（学期起止↔教学周/考试周）、`ScheduleAdjustment`（调休：校历 kind=2 的工作日替换）、`TimetableResolver`、`TimetableIcs`（ICS 导出）。

**兜底导入**：课表截图 → 多模态 LLM 识别 → 结构化 → 用户确认后入库。

### 4.2 作业采集适配器

```dart
abstract class SourceAdapter {
  String get sourceId;                 // 'canvas' | 'onetongji_webview' | 'manual'
  String get displayName;
  AuthRequirement get auth;            // none | token | oauth | webviewLogin
  Future<List<RawItem>> fetch();       // 原始条目
}

class RawItem {                        // 未解析的中间形态
  String sourceRef;                    // 去重键：源内唯一标识（Canvas assignment id / 通知 url / 内容hash）
  String? courseHint;                  // 课程名线索（可能为空）
  String title;
  String rawText;                      // 富文本原文
  DateTime? dueAtHint;                 // 源里已有的时间线索（Canvas 有精确值）
}
```

**Canvas 适配器**（主力，结构化程度最高）：

- 用户在自己的 Canvas 网页：设置 → 生成 access token，粘贴进 Jinah 凭据页。
- `GET /api/v1/courses?enrollment_state=active` → 每课 `GET /api/v1/courses/:id/assignments?include[]=submission`。
- 返回即结构化（name / due_at / html_url / points_possible / has_submitted_submissions），**无需 AI 解析**，直接映射 TODO + 完成状态回写。

**1系统 WebView 捕获**（通知 → AI 解析）：

- 复用课表链路 B 的 WebView 登录态，拦截首页通知列表/详情接口（路径待实测确认，参考 `msg_list` 前端调用）。
- 通知富文本进 AI 解析管线，提取：课程、任务内容、截止时间、提交方式。

**手动/分享**（兜底，覆盖微信/QQ）：

- Android 接收系统分享（文字/图片）、剪贴板粘贴、应用内输入。
- 文本直接进解析；截图走多模态模型。

### 4.3 AI 解析管线

```
RawItem → [有结构化字段?] ──是──→ 直接映射 TodoItem（Canvas 路径）
              │否
              ▼
        Prompt 组装（系统提示：同济课程场景、输出 JSON Schema）
              ▼
        客户端直连 LLM API（OpenAI 兼容协议，用户自备 key+base_url，推荐便宜模型即可）
              ▼
        JSON Schema 校验（失败→重试一次→仍失败则原文进 TODO 标题、标"待补充"）
              ▼
        TodoItem 草稿 → 用户确认（一期：手动来源默认进确认页，自动来源直接入库标来源）
```

- 解析 Prompt 要求输出：`{course, title, due_at, submit_method, confidence, raw_quote}`。
- `due_at` 必须给绝对时间（结合校历学期信息换算"周五"这类相对表述）。
- 同一 sourceRef 去重；跨来源重复（Canvas 已收、群里又转发）按标题+截止时间相似度提示合并。

### 4.4 TODO 与提醒

- 本地 Drift 数据库存储；状态机：`open → done / dismissed`。
- 截止前本地通知（flutter_local_notifications）：默认 D-1 20:00 和当天 08:00 两档，可配。
- 列表视图：按截止时间排序 / 按课程分组 / 只看本周。完成态可手动勾选（Canvas 作业已完成从 API 回写）。
- 导出 JSON 备份 / 导入恢复；ICS 导出（作业截止也能进系统日历）。

### 4.5 界面与交互（Obsidian 设计语言）

整体采用 Obsidian 的界面风格：深色优先、低饱和、文字与信息密度优先于装饰。

**配色**（对齐 Obsidian 设计 token）：

| Token | 深色 | 浅色 |
|---|---|---|
| 主背景 background-primary | `#1e1e1e` | `#ffffff` |
| 侧栏/次背景 background-secondary | `#262626` | `#f2f3f5` |
| 边框 background-modifier-border | `#363636` | `#e1e4e8` |
| 正文 text-normal | `#dcddde` | `#222222` |
| 次要文字 text-muted | `#999999` | `#8a8a8a` |
| 强调色 interactive-accent | `#7f6df2`（Obsidian 默认紫） | 同左 |

**布局**：左侧边栏导航（课表 / TODO / 解析收件箱 / 设置），可折叠；右侧主内容区。桌面与平板同构，手机端侧边栏变抽屉。

**组件借用**：

- TODO 条目 = Obsidian 任务列表样式：复选框 + 文字 + 标签 pill + 静音色截止日期
- 课程名以 pill 呈现，颜色映射课程色（如同 Obsidian 标签）
- 课表网格：细边框 + 低对比底色，当前课时用 accent 细条标记
- **命令面板**（`Ctrl/Cmd + K`）：快捷添加 TODO、跳转页面、立即同步——Obsidian 的灵魂交互，效率工具必配
- 悬浮设置面板（Obsidian 式 modal），而非独立设置页
- 圆角与阴影克制（小圆角、几乎无阴影），hover 态用背景色变化表达

**字体**：系统无衬线优先（中文回退系统字体），等宽仅用于截止时间与代码类内容。

**主题**：默认深色，设置里手动切换浅色（已确定，不做"跟随系统"）。强调色默认紫 `#7f6df2`，设置里可自定义（已确定）。

### 4.6 凭据管理

统一设置页，三类凭据：Canvas token / 开放平台 client_id(+secret) / LLM key+base_url。

- 存 `flutter_secure_storage`（Keychain/Keystore），排除系统云备份。
- 永不写日志、永不随备份导出、永不出现在崩溃上报。

## 5. 数据模型（草案）

```
Term            { id(calendarId), name, startDate, endDate, teachWeeks, examWeeks }
Course          { id, code?, name, teacher?, color, source, sourceRef }
ScheduleEntry   { id, courseId, weekday(1-7), startPeriod, endPeriod, weekSet, location?, rawWeekText }
SchoolDay       { date, kind(1节假日 2调休工作日 3周末 4寒假 5暑期) }
TodoItem        { id, title, courseId?, source(canvas|notice|manual|screenshot),
                  sourceRef, detail?, dueAt?, status, createdAt, completedAt, notifiedFlag }
Credential      { type(canvas|openplatform|llm), payload(json), updatedAt }
```

Canvas 课程 ↔ 本地 Course 的映射：先按名称模糊匹配，匹配不上进"未绑定"列表让用户手动指定（课程重名/简称普遍存在）。

## 6. 风险与维护成本（要有心理准备）

| 风险 | 应对 |
|---|---|
| 统一身份认证出验证码/改流程 | WebView 里用户手动过验证码；不适配滑块等强交互，提示改用链路 A |
| 1系统前端改版，捕获路径失效 | 适配器模块化，单点修；TJTimetable 的适配器测试模式照抄（真响应样本进测试） |
| Canvas token 过期/重置 | 捕获 401 → 通知用户重新粘贴 token |
| LLM key 无效/欠费 | 解析管线降级：原文直接进 TODO 标题，不阻塞采集 |
| 学校政策变化（开放平台审批收紧） | 链路 B 不依赖审批，始终是备胎 |

## 7. 待定项（开发前需拍板）

1. **状态管理**：建议 Riverpod（简洁、可测），待确认。
2. **AI 解析确认流**：手动来源是否一律过确认页（建议：是；置信度高的给"一键全部确认"）。
3. **仓库名/包名/应用名**：`Jinah` 是否最终定名，org 标识待定（如 `org.jinah.app`）。
4. **开源许可证**：建议 MIT（宽松利于传播）或 AGPL（防闭源商用），待选。
5. **校历/学期缓存策略**：免 token 接口建议首次启动即拉取并缓存本地（离线可用 + 未登录也能展示调休）。

## 8. 参考资产

- TJTimetable 源码（本作者）：课表双链路、领域逻辑、ICS、提醒，移植首选。
- 开放平台接口全量清单：`GET https://api.tongji.edu.cn/v1/openplatform/api/get_api_list`（234 个接口，无作业接口；校历/学期免 token；另有 `v1_infra_calendar_*` 日程、`v1_ai_tools_file2md` OCR 可供二期探索）。
- Canvas API：标准 Instructure，文档 canvas.instructure.com。
- TongjiWebCapture 设计来源：`gzy31007/TJDesktopTimetable`（.NET 实现）。
