# 来源算法运行骨架：检查记录

日期：2026-10-12。项目：`C:\Users\haige\Desktop\Playra`。

结论：运行骨架 PASS。真实影视来源、真实加解密和 Android 真机播放尚未接入或验证，不属于本轮完成项。

## 行为与集成证据

| 检查 | 结果与范围 |
| --- | --- |
| Python `unittest discover -s tool/source_runtime -p test_server.py -v` | 5 项 PASS；真实 HTTP、默认空能力、请求限制、分页、业务错误、超时与断开上下文 |
| Node `--test tool/web_backend/runtime.test.cjs tool/web_backend/security.test.cjs` | 8 项 PASS；固定转发、默认禁用、路由限制、请求/响应限制、超时及既有代理安全回归 |
| Flutter `test --no-pub test/source_runtime_test.dart test/source_service_test.dart test/rule_engine_test.dart` | 33 项 PASS；包含 9 项新增运行契约测试，普通请求原样委托、未配置原生地址、HTTP 显式开关、取消和错误保留 |
| `tool/source_api_integration.dart` | 原有真实 HTTP 来源 API 的 32 项检查 PASS |
| `tool/source_runtime_integration.dart` | 21 项 PASS；独立 Python fixture + 独立 Node 服务 + 实际 RuleEngine / SourceService，覆盖直连与 Web 桥接、分页、真实线路/特殊集名称、解析头与有效期、空资源与解密错误区分、取消 |
| Dart 定向静态分析 | No issues found：运行客户端、Flutter 请求器、来源服务、HTTP 外观与运行契约测试 |
| Node / PowerShell 语法 | Node 桥接与服务器语法 PASS；Web 和 Android 启动构建脚本 AST 检查 PASS |

测试 fixture 仅供检查，不进入生产适配器登记、不自动导入示例规则，其媒体 URL 不代表可播放的真实影视资源。

## 实际 Web 调用

使用实际启动命令：

```powershell
py -3.13 -X utf8 tool/source_runtime/server.py --port 8945
$env:KAZUMI_WEB_ROOT=(Resolve-Path '.dart_tool/runtime-browser-probe').Path
.\tool\start-web.ps1 -Port 8936 -RuntimePort 8945 -NoOpen
```

诊断页使用 `dart compile js` 编译的真实 `SourceRuntimeClient`，由 Playwright 在浏览器访问。页面输出：

```json
{"endpoint":"http://127.0.0.1:8936/api/runtime/v1/","health":{"service":"playra-source-runtime","status":"ok","apiVersion":"1","adapters":1},"template":"UNSUPPORTED","status":"PASS"}
```

浏览器出现的单条 HTTP 422 是预期的模板 `UNSUPPORTED` 响应；没有把未实现的接口报告为成功资源。诊断文件位于忽略目录 `.dart_tool/runtime-browser-probe/`，不进入应用资源。验证结束关闭诊断浏览器、停止本轮 8936 / 8945 服务，保留原有 8933 首页服务。这项检查证明浏览器运行调用链，不是全页面视觉回归。

## 编译与产物

Web：`flutter build web --no-pub --no-wasm-dry-run` PASS，实际入口 `lib/main.dart`，产物 `build/web/main.dart.js`，7,332,497 字节。没有替换原来 8933 服务的预览目录。

Android：实际运行更新后的 `tool/build-android.ps1`，使用 `C:/Android/Sdk` 和 JDK 21，配置 `http://127.0.0.1:8945/v1/` 开发运行地址及显式 HTTP 开关，`assembleDebug` PASS。

- APK：`build/app/outputs/flutter-apk/app-debug.apk`
- 大小：184,165,980 字节。
- SHA-256：`F0F528C023B06A9870C2BCC0D59B4C6F25DED382DC0CB4565350EBA72CC32DA9`。
- ZIP CRC 完整性 PASS；含 AndroidManifest 与 `arm64-v8a / armeabi-v7a / x86_64` Flutter 库。
- 未安装到设备、未删除设备数据，未声称已完成 Android 真机连接或播放。
- 现有 AGP / Kotlin 版本提示未阻断构建，本轮未升级工具链或依赖。

该 APK 是开发检查产物。若主动导入运行模板并调用，需要先运行 Python 服务、连接设备并设置 `adb reverse`；模板仍会返回 UNSUPPORTED。后续发布构建应配置正式 HTTPS 地址。

## 修改清单与影响

| 文件 | 本轮目的 |
| --- | --- |
| `lib/services/source/runtime/*` | 跨平台基址、受限 HTTP 客户端、规则请求装饰器 |
| `lib/services/plugin/rule_engine_runtime_flutter.dart` | 接入装饰器，原规则继续委托原请求器 |
| `lib/services/source/source_service.dart` | 保留引擎包装后的运行错误码 |
| `lib/services/source/source_http_server.dart` | 独立 HTTP 外观复用同一运行请求契约 |
| `tool/source_runtime/{server.py,adapters.py,example-rule.json}` | Python 协议服务、适配器模板和未安装示例 |
| `tool/web_backend/{runtime.cjs,server.cjs}` | 可关闭的固定本机 Web 桥接 |
| `tool/start-web.ps1` | 显式运行端口与健康预检，不杀旧服务 |
| `tool/build-android.ps1` | 运行地址与开发 HTTP 构建参数 |
| `test/source_runtime_test.dart`、`tool/source_runtime/test_server.py`、`tool/web_backend/runtime.test.cjs` | 契约和边界测试 |
| `tool/source_runtime/{integration_fixture.py}`、`tool/source_runtime_integration.dart` | 隔离的真实 HTTP 规则调用链验证 |
| `openspec/changes/scaffold-source-algorithm-runtime/*` | 规范、设计和完成项 |
| `docs/source-algorithm-runtime.zh.md`、本文件 | 接入操作与证据边界 |

针对本轮开始时保存的 1049 个文件 SHA-256 对比，仅六个预定的既有文件发生变化。其余已记录文件保持原样，包括 16 条内置动漫规则与依赖锁文件；未撤回此前工作区修改。新增文本严格 UTF-8、无 BOM、无 U+FFFD；既有六文件保持原换行方式，`git diff --check` 无空白错误。

曾尝试新增单独 PowerShell 启动帮助文件，但文件出现后被本机移除，原因未确认；没有修改防护设置或绕过访问限制。最终采用直接 Python 前台 CLI，不依赖该文件。

## 回滚与后续

六个既有文件的修改前副本以及本轮前文件哈希保存在 `.dart_tool/runtime-skeleton-before-20261012/`。回滚只恢复本轮差异，删除本轮新增运行文件，关闭运行桥接参数；不要整体重置已有工作区。该备份目录为本机缓存，应在清理前保留。

NEXT：取得真实影视接口协议后，在登记适配器中实现请求、签名和解密；按真实能力补齐会话、鉴权及生产 HTTPS 部署，再验证对应 Web / Android 媒体播放。当前服务健康状态不代表这些能力已经完成。
