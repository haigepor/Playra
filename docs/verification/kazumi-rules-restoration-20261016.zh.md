# Kazumi 原 16 条规则恢复与画质验收

日期：2026-10-16；分支：`codex/restore-kazumi-anime-rules`；基线：`649ab05e`。

本页保留初轮恢复与验收记录。后续已修复部分解析链路，并确认真实 1080p 样本；最新结论见[第二轮故障排查与线路筛选](kazumi-1080p-lines-20261016.zh.md)。以下“尚无成功样本”等表述仅描述初轮时点。

## 1. 范围和来源

按用户确认，恢复原 16 条规则，以“动漫 · Kazumi”替换默认 AniFive 四源，保留 Lumina/MioMedia。自动选线仅接受实际解码高度 ≥1080，未知或低清保留手动入口。不是删除不能证明整站 1080p 的规则，也不承诺原 16 个站点全部可用。

官方应用参考提交：[025dcb5c](https://github.com/Predidit/Kazumi/tree/025dcb5c2f62db881382c72f191d08b49a9feb41)。官方规则固定提交：[135ef2c2](https://github.com/Predidit/KazumiRules/tree/135ef2c2ef2a09f6fbde0f73957403b2c03bfe00)。当前上游额外的 LMM 未纳入，名单来自项目原 16 条快照。

恢复名单：`7sefun / aafun / AGE / akianime / baimao / dalvdm / DM84 / ezdmw / giriGiriLove / mgnacg / moonci / mutefun / MXdm / sorani / xfdmneo / xfdmnext`。

每份 JSON 保持固定提交的规则字段，只增加受管来源元数据；原始字节 SHA256、规范化规则 SHA256、版本和旧四源快照位于 `assets/migrations/kazumi-v1.json`。复核命令：

```powershell
node tool/import_kazumi_rules.mjs --verify
# 可重放导入已核对的上游原始文件；不使用站点镜像或修改默认线路。
node tool/import_kazumi_rules.mjs --input-dir .dart_tool/kazumi-restoration-20261016/reference/rules
```

## 2. 能力、字段与平台

Kazumi 走现有 `RuleContentProvider → SourceService / RuleEngine → Plugin`，使用真实 Bangumi 资料身份，分组 ID 为 `kazumi`，没有 Python adapterId。规则仍以各站 sourceId、作品 URL、原线路索引、真实剧集 URL 作为执行身份。

| 能力 | 本次实现与边界 |
|---|---|
| 搜索、目录、线路、剧集 | 官方 XPath / JSON API；保持上游返回顺序与集号，保留倒序目录，不编造缺集 |
| API 9 | 增加 `sourceTemplate` 与 `@source` URL 编码替换；保留现有封面等扩展 |
| 详情与封面 | 复用 Bangumi 资料与既有请求头策略；没有新增站点首页、榜单或原生 SDK 目录能力 |
| 解析 | 官方规则决定普通嗅探或简易 iframe 解析；Web 将 `useLegacyParser` 传递至 Node，保留媒体签名查询参数 |
| 自动画质 | 首帧后最多等待约 3 秒获取实际解码尺寸，帧高 ≥1080 才确认自动线路；720p、1920×800 和未知尺寸拒绝自动确认，继续既有同集回退预算 |
| 手动播放 | 低清、未知尺寸仍可手动选择；Lumina/MioMedia 的策略不受本次画质限制影响 |
| 持续播放与 ABR | 只验证启动时尺寸，不是全程清晰度锁定；没有伪造可选画质 code |
| 下载、seek、历史 | 复用既有机制；本轮未新增能力，真实下载、拖动和跨平台实播未验收 |

Web：生产规则请求器 → Node 同源网关 → 官方站点；播放页 → 受限 Chromium 解析 → 媒体代理 → 原有单播放器。

Android：复用既有原生规则请求与 WebView 解析、媒体播放器。此次只移除已不需要的 AniFive 强制输入检查，保留旧适配器兼容代码；未改 Kotlin 通道或私有 SDK 协议。iOS/桌面原生构建和实播未验收。

解析目标继续校验公网地址、协议、凭据和跳转；只为实测官方 AGE 嵌入播放器增加 `jx.wuzhoupai.com:8443` 精确 HTTPS 端口例外，没有开放任意端口。没有绕过登录或人工验证。日志和交付文档不保存完整媒体签名地址、Cookie 或设备身份。

## 3. 迁移、状态与回退

迁移使用原 16 条快照、旧 AniFive 四源快照和新官方资产进行内容指纹比较。仅替换未修改的旧内置规则，保留本地名称和稳定 sourceId；用户改过的规则和同名自定义项保留，发生冲突时给官方规则分配独立身份。新默认资产中不再有 `source-runtime.playra.invalid` AniFive 调用。

首次迁移在应用规则存储目录生成 `plugins.before-kazumi-v1.json`、`source-policy.before-kazumi-v1.json`，成功保存后写 `kazumi-v1.complete`。重试不覆盖首次备份。已完成迁移后的启动只更新受管版本，不重新安装用户删除的规则。历史恢复遵循同站身份，不按片名跨源迁移；原 aafun、moonci 已分别存在，不再把 aafun 自动合并为 moonci。

代码回退基线为 `649ab05e`，本轮尚未提交；本机先前文件副本位于 `.dart_tool/kazumi-restoration-20261016/before/`。回退时逐文件恢复本轮改动，应用数据恢复上述两份迁移备份并删除新迁移标记；恢复数据前备份当前规则，避免覆盖迁移后的用户编辑。工作区原有 `recipes.json` 和脏子模块 `fastlane/.libmpv-android-video-build` 未修改，不应清理或重置。

## 4. 自动化与构建收据

| 门禁 | 结果 | 证据 |
|---|---|---|
| 原 16 条名单、来源元数据、摘要 | PASS | `node tool/import_kazumi_rules.mjs --verify` |
| Dart 共享回归 | PASS | 18 个测试文件、125 项通过：规则、迁移、SDK 分组、API、来源服务、请求头、历史、播放器启动和手动画质 |
| Node 网关与 Chromium 解析回归 | PASS | `node --test *.test.cjs`，42 项通过；含实际 Chromium 简易解析、取消、端口、代理、HLS/Range 与 SDK 桥 |
| 定向分析 | PASS（有提示） | 13 个目标，无错误/警告，8 项 style info；不宣称零诊断 |
| UTF-8、BOM、差异范围 | PASS | 48 个本轮文本文件严格 UTF-8、无 BOM/U+FFFD；`git diff --check` 和范围检查通过，原有两个工作区改动单独排除 |
| 最新 Web 构建 | PASS | `flutter build web --no-pub`，84.8 秒，`build/web/` |
| Android Debug 构建 | BLOCKED | `flutter build apk --debug --no-pub`：`:app:stageEmbeddedPython` / `Missing Lumina SDK: run tool/source_runtime/import_lumina.py; see docs/release/build-inputs.zh.md` |
| Android 安装与实播 | BLOCKED | 收尾复查时 ADB 已出现 `emulator-5554`；但缺 Lumina 输入使本轮 APK 无法生成，不使用旧 APK 作为验收证据 |
| CI、正式签名、干净克隆 | 未验证 | Lumina 私有输入尚未恢复；本轮没有发布 |

Flutter 回归命令：

```powershell
flutter test --no-pub test/kazumi_rules_test.dart test/kazumi_migration_test.dart test/source_sdk_group_test.dart test/bundled_anime_migration_test.dart test/content_provider_test.dart test/api_rule_engine_test.dart test/plugin_api_config_test.dart test/anifive_history_identity_test.dart test/cold_history_resume_test.dart test/source_service_test.dart test/source_header_policy_test.dart test/rule_engine_test.dart test/anime_playback_quality_test.dart test/video_startup_recovery_test.dart test/modern_player_contract_test.dart test/sdk_playback_coordinator_test.dart test/sdk_manual_quality_test.dart test/source_media_player_test.dart
```

## 5. 真实 HTTP 和浏览器证据

使用隔离 Node 网关 `18936` 与现有源码服务 `18937`，没有替换真实站点响应。`tool/kazumi_live_check.dart` 使用生产 RuleEngine / SourceService，检索“吞噬星空”，按官方首条线路取真实目录。记录位于 `.dart_tool/kazumi-restoration-20261016/`。

| 检查 | 结果 |
|---|---|
| 16 条搜索 | 15 条请求完成；dalvdm 为 SOURCE_ERROR。完成包含空结果，不等同所有来源有该作品 |
| 可匹配的目录 | 7sefun、AGE、DM84、MXdm、baimao，分别 1/8/1/4/6 条；其他来源未取得同名样本 |
| AGE、7sefun、DM84、baimao 默认线经网关解析 | HTTP 502 / 未找到媒体；仍是未通过的真实起播验收 |
| MXdm | 页面解析得到媒体，但代理请求 HLS 为 HTTP 403；初次 `live.json` 将媒体错误记进 parse 字段，脚本后续已拆分 mediaError。不能据旧字段称解析本身 403 |
| 最新 Web 页面 | Playwright MCP 实测搜索、详情、Kazumi 分组、官方线路列表和手动入口；显示“自动仅选实测 ≥1080p；低清或未知画质可手动选择” |
| 直接官方 AGE 默认线路 | “吞噬星空”第 1 集，`/play/20200358/1/1`，实际视频 **864×486**、readyState=4、播放时间递增，低于门槛 |
| 直接官方 baimao 默认线路 | `/play/244239-0-0.html` 跳转当前站域名 bmmdmm.com；实际视频 **1080×608**、readyState=4，低于门槛（宽度1080不是1080p） |
| 真实 ≥1080p 成功样本 | 未确认，不能把自动策略单元测试当作真实站点 1080p 实播通过 |

最新线路截图/DOM：`.dart_tool/kazumi-restoration-20261016/latest-lines.png`、`latest-lines.yml`；点击自动选择后的状态：`latest-automatic.png`、`latest-automatic.yml`。页面确认自动状态与官方聚合线路，但仍受解析失败影响；不能将 UI 状态当作自动起播成功。浏览器控制台中来源失败与隔离环境未启动 Lumina/Mio 算法服务的错误已观察到，不归类为零错误通过。

## 6. 修改文件、影响和结论

| 文件范围 | 目的和影响 |
|---|---|
| `assets/plugins/*.json`、`assets/migrations/kazumi-v1.json`、`tool/import_kazumi_rules.mjs` | 原 16 条官方资产、固定版本、迁移快照与可重放校验 |
| `lib/plugins/`、`lib/request/config/api_endpoints.dart`、`lib/services/plugin/api_rule_strategy.dart`、`lib/services/source/source_service.dart`、规则编辑页 | API 9 模板、受管迁移与更新保护；保留旧兼容契约 |
| `lib/services/source/source_sdk_group.dart`、`source_display_names.dart`、现代详情页 | Kazumi 默认分组与官方目录渲染 |
| `lib/services/source/anime_playback_quality.dart`、`lib/pages/video/video_controller.dart` | 自动线路实测画质门槛、手动入口与取消保护 |
| WebView 浏览器实现、`tool/web_backend/parser.cjs`、`security.cjs` | 传递官方简易解析标志与最小端口兼容 |
| `android/app/build.gradle`、`tool/start-web.ps1` | AniFive 私有输入变为旧规则可选项，其他 SDK 检查保留 |
| `test/`、Node 解析/安全测试、`tool/kazumi_live_check.dart` | 迁移、规则、画质、共享回归和真实站点审计 |
| 构建输入、接入规范、本记录 | 更新当前契约、依赖、验证和回退说明 |

总体交付状态 **PARTIAL**：代码、16 条规则恢复、迁移、画质门槛、Web 构建和自动化回归完成；真实默认线路的端到端起播验收未通过，尚无 ≥1080p 真实成功样本；Android 构建和实播被缺私有输入阻塞。不能宣布 16 条均可播放或筛出稳定 1080p 站点白名单。

- DONE：原 16 条恢复、Kazumi 分组、替换默认 AniFive、官方目录与解析接入、自动画质门槛、回归测试。
- BLOCKED：真实 ≥1080p 起播确认与默认线路完整验收；需可用媒体样本/网络条件，并针对现有 502/403 继续诊断。
- BLOCKED：Android 构建和设备实播；需恢复 Lumina 私有输入、构建本轮 APK 后在现有模拟器验收。
