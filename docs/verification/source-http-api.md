# 来源服务与 HTTP API 验收记录

日期：2026-10-11。OpenSpec 变更：`unify-source-services-http-api`。

## 实现范围

六项需求均已落实：统一来源身份/能力/DTO；新旧搜索与剧集共用 RuleEngine；首页目录适配器迁出展示层；保留各平台解析及验证码实现并引入会话/取消上下文；分页、分类和按操作健康；可独立启动的 HTTP API 与 Web 同源转发。

应用默认本地执行；外部调用方通过 HTTP API 或 SourceHttpClient 调用同一规则核心。不是把第三方网站改造成原生 JSON 服务。没有改动依赖版本、全局工具配置、用户收藏/历史或本次之前的首页视觉修改。

## 验证结果

| 检查 | 状态 | 证据 |
|---|---|---|
| 来源模块、纯 Dart/Flutter 运行时、入口与契约测试静态检查 | PASS | `dart analyze`：No issues found |
| 既有调用方静态检查 | PASS | 无错误/警告；video_controller.dart:250 有一个原有 null-aware 风格提示 |
| 来源、混合规则、JSON 兼容、API 引擎、搜索解析、目录匹配、导航回归 | PASS | 83 项通过；命令与输出见 `.dart_tool/source-focused-tests.log` |
| 实际本机 HTTP + RuleEngine + 网关 fixture | PASS | 32 项，含 GET/POST JSON、分页、SP/OVA、部分失败、同名来源隔离、会话隔离、解析/取消、验证码、媒体/HLS 和请求体限制 |
| 实际 Chromium 解析/验证/取消 | PASS | 3 项；取消在页面创建/导航期间生效，取消后可再次解析 |
| 官方规则加载 | PASS | `--catalog` 启动后注册 16 个来源；不代表每个站点都可用 |
| 真实 DM84 搜索与剧集 | PASS | CLANNAD 返回 3 项；第一项线路 1 条、剧集 1 项，名称 HD高清 |
| 浏览器同源接口 | PASS | 8933 的 health/sources/session/categories 正常；未授权搜索 401 为预期错误 |
| 真实 DM84 国漫目录 | PASS | 分类 CN/source_directory；已抓取集合 total=36，本地分页，warnings 为空 |
| 首页浏览器回归 | PASS | 推荐四卡与动漫子分类渲染、切换正常；截图 `source-api-home-web.png`。控制台只有故意发起的未授权接口 401 |
| Web、Android、Windows 构建 | PASS | 首页 Web bundle、debug APK 和 Windows debug exe 均构建成功 |
| Android 模拟器安装与启动 | PASS | emulator-5554 安装 Success；系统解析的 com.example.kazumi.MainActivity 冷启动 Status: ok |
| 原生平台完整播放/验证码 | 未验收 | 本次未进行 Android/Windows 完整原生播放和验证码实测；模拟器启动不能替代这些检查 |
| 首页历史用例扩展回归 | FAIL | modern_home_controller/view 共 6 项失败，详见下段 |
| OpenSpec 与编码/范围 | PASS | 严格校验、UTF-8 和 diff whitespace 检查 |

首页扩展回归失败已保留在 `.dart_tool/source-home-regression.log`：旧 fixture 仅构造 chinese/japanese/airing，没有当前首页所需的 algorithm/subjects；旧测试仍定位主栏的新番按钮，以及先前的错误提示。当前首页控制器、视图和这两个测试文件在本次开始前已有修改，本次没有编辑它们。失败用例通过注入 loadCatalog/loadFeed 执行，未调用此次迁移的真实目录加载器。不能把这批失败报告为通过；后续应单独同步这些首页用例与当前数据和导航契约。

构建工具仍提示现有 Gradle/AGP/Kotlin 后续版本支持变化及 Windows 插件 CMake/NuGet 信息；这次未升级工具链，构建结果成功。

## 本次文件与影响

| 文件/目录 | 目的与影响 |
|---|---|
| `lib/services/source/` | 新增模型、共享服务、目录注册、原生解析包装、HTTP 网关/服务/客户端 |
| `lib/services/plugin/rule_engine.dart`、新增 `rule_engine_runtime_flutter.dart` / `rule_engine_runtime_standalone.dart` | 条件运行时隔离；保留 XPath/JSONPath 核心，增加分页变量 |
| `lib/plugins/plugins.dart`、`plugins_controller.dart` | 可选身份/扩展配置兼容，安装更新保留身份，旧入口委托共享服务 |
| `lib/services/plugin/plugin_search_service.dart` | 既有页面聚合搜索并发限 4，保留旧 UI 状态与过期结果保护 |
| `lib/presentation/modern/home/home_rule_catalog.dart` | 保留已有展示模型；规则名称和站点选择器移至服务层，保留只读内置兜底与优先顺序 |
| `lib/pages/video/video_controller.dart`、`lib/services/video_source/video_source_resolver_pool.dart`、`lib/pages/download/download_controller.dart` | 原生/浏览器播放下载使用统一来源身份及解析上下文 |
| `lib/services/plugin/captcha_verification_service.dart`、`lib/pages/info/source_sheet.dart`、`source_captcha_flow.dart` | 接入验证码上下文，保持既有 Cookie/页面收割及取消流程 |
| `tool/web_backend/server.cjs` / `parser.cjs` / `parser.test.cjs` | 固定本机 API 转发、服务端播放上下文、取消浏览器资源与回归 |
| `tool/source_api.dart`、`tool/source_api_integration.dart`、`test/source_service_test.dart` | API 入口、实际 HTTP fixture 与契约测试 |
| `openspec/changes/unify-source-services-http-api/`、`docs/source-http-api.md`、本记录和截图 | 规范、调用说明、范围与验收证据 |

## 启动与回滚

运行入口、请求示例、字段与限制见 `../source-http-api.md`。预览同源 `/api/v1` 转发到本机 8940；两种地址共用服务实例。Web 日志和进程标识位于 `.dart_tool/source-api-runtime/`，来源 API 日志输出在启动终端。

回滚只撤回上述兼容入口的服务委托、原生解析包装与 Node 新增转发，然后停用新增来源 API。保留用户安装规则和业务数据；可选 sourceId/sourceConfig 不需要删除。工作区原有首页修改尚未提交，不应对整个目录或这些首页文件执行 git restore。此记录的文件清单用于定位回滚范围，OpenSpec 的 design.md 保留迁移决策。

整体交付：来源服务与 API 契约通过；原生完整播放验收和 6 项首页历史测试同步留作明确限制。
