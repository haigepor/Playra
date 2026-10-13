# Web / Android 开发环境与多设备路径

适用：Playra 当前主线的 Windows 开发电脑，目标平台为 Web 与 Android。仓库根目录以你实际克隆的位置为准；下文命令均在仓库根目录执行。

## 1. 路径分工

| 类别 | 位置或入口 | 随 Git 同步 | 新设备的处理 |
| --- | --- | --- | --- |
| 源码与版本约束 | `pubspec.yaml`、`pubspec.lock`、`android/settings.gradle`、`tool/web_backend/package-lock.json` | 是 | 拉取对应提交，保留锁定版本 |
| 环境入口与模板 | `tool/use-dev-env.ps1`、`tool/dev-environment.example.json` | 是 | 使用模板创建本机配置 |
| 本机工具路径 | `.tooling/dev-environment.json` | 否 | 根据本机安装位置重新填写 |
| 项目专用工具 | `.tooling/flutter`、`.tooling/python`、`.tooling/node`、`.tooling/java` | 否 | 安装匹配版本；也可通过本机配置指定外部工具目录 |
| Android SDK | 本机配置的 `androidSdk` | 否 | 可以共享同一台电脑的 SDK，例如本机的 `D:/Android/Sdk` |
| 依赖缓存 | `.tooling/pub-cache`、`.tooling/gradle`、`.tooling/npm-cache`、`.tooling/playwright-browsers` | 否 | 在新设备重新恢复；不把旧电脑缓存路径当作配置 |
| 私有 SDK | `tool/source_runtime/vendor/miomedia` | 否 | 从授权的完整 SDK 源目录执行同步，再运行自检 |
| Android 签名材料 | `android/key.properties`、对应 keystore | 否 | 正式签名单独准备；测试包不代表正式发布 |
| 生成的路径与插件文件 | `.dart_tool/package_config.json`、`.flutter-plugins-dependencies`、`android/local.properties`、平台 ephemeral 目录 | 否或由工具生成 | 由本机 `flutter pub get` 和构建重新生成 |
| 构建产物 | `build/web`、`build/modern-home-preview`、`build/app/outputs/flutter-apk` | 否 | 重新构建；检查当前文件时间和哈希 |
| 设备与服务身份 | Web 默认 `.dart_tool/miomedia/device.json`；Android 应用私有目录中的 `miomedia/device.json` | 否 | 各设备独立保存，不能随整个工作区批量复制身份 |
| 验证与历史记录 | `docs/verification` 中的文字和截图 | 是 | 作为历史证据，不假定旧机器上的路径、APK、设备仍然存在 |

`tool/dev-environment.example.json` 中的 `D:/Android/Sdk` 只是本机示例；另一台设备可以使用其他盘符。仓库内的工具路径使用相对路径，环境脚本根据自己的位置解析，移动检出目录时无需逐项更换项目盘符。

## 2. 本机已经准备的版本

| 组件 | 版本与位置 |
| --- | --- |
| Flutter / Dart | Flutter 3.47.6、Dart 3.13.5；`.tooling/flutter` |
| Python | CPython 3.11.15；`.tooling/python/cpython-3.11.15-windows-x86_64-none` |
| Node.js / npm | Node 22.23.3；`.tooling/node/node-v22.23.3-win-x64`；npm 随 Node 提供 |
| JDK | Temurin 17.0.20.1；`.tooling/java/jdk-17.0.20.1+1` |
| Android | SDK Platform 36、Build Tools 36.0.0、NDK 28.2.13676358、CMake 3.22.1、Ninja；本机位于 `D:/Android/Sdk` |
| Gradle / AGP / Kotlin | 项目 wrapper 8.14.5、AGP 8.11.1、Kotlin 2.2.21 |
| 内置 Python | Chaquopy 17.0.0、Python 3.11；与构建机 Python 主次版本一致 |
| Web 解析浏览器 | Playwright 1.62.1 对应 Chromium、Headless Shell、FFmpeg、Winldd；`.tooling/playwright-browsers` |
| MioMedia | 原 SDK 的 12 个核心文件加 `_native/__init__.py`，共 13 个运行输入；Windows DLL 不进入 Android 包 |

以上是本机的已安装版本，不是对所有新机器的存在性保证。Flutter、Android 插件、NDK 和 npm 包仍以仓库配置与锁文件为准，不能各自更新到最新版本后跳过兼容检查。

Windows 主机单元测试中的原生 C/C++ 构建还会使用本机已注册的 MSVC/Windows SDK；本机 MSVC 位于 `C:/VSBuildTools2022`。Windows 系统组件沿用系统安装，项目工具、包与缓存放在 D 盘。Android 交叉编译使用配置的 Android SDK/NDK。新设备只做 Web/Android 开发时，环境脚本在当前进程关闭桌面平台生成，避免 `pub get` 为桌面插件请求符号链接权限。

## 3. 新设备配置顺序

1. 克隆 Playra `main` 到你选择的目录，不复制旧电脑的 `.dart_tool`、`build` 或 `android/local.properties`。
2. 安装对应 Flutter、Python 3.11、Node 22、JDK 17 和 Android SDK/NDK。项目内目录按上表放置；已有共享安装也可使用。
3. 创建本机环境文件：

```powershell
New-Item -ItemType Directory -Path .tooling -Force | Out-Null
Copy-Item -LiteralPath tool/dev-environment.example.json -Destination .tooling/dev-environment.json
```

4. 编辑 `.tooling/dev-environment.json`：工具版本目录填写本机真实名称；`androidSdk` 填本机的 SDK 根目录。`flutterHome`、`python`、`nodeHome`、`javaHome` 可以是仓库相对路径，也可以是绝对路径。相对路径始终相对于仓库根目录，不相对于当前终端目录。
5. 在每个开发终端激活并恢复依赖：

```powershell
. ./tool/use-dev-env.ps1
flutter pub get --enforce-lockfile
npm.cmd ci --prefix tool/web_backend --ignore-scripts --no-audit
node tool/web_backend/node_modules/playwright/cli.js install chromium
```

第一次下载浏览器后再次激活环境，让脚本按 Playwright 的浏览器清单选取本机 Chromium：

```powershell
. ./tool/use-dev-env.ps1
Get-Command flutter,dart,python,node,java,cmake,ninja,adb | Select-Object Name,Source
```

6. 准备私有 SDK。下面的路径是占位符，只替换为本机授权 SDK 的 `miomedia` 目录，不复制旧电脑用户名：

```powershell
python tool/miomedia_sdk_input.py sync --sdk-directory "本机授权SDK目录/miomedia"
python tool/miomedia_sdk_input.py check
Push-Location tool/source_runtime/vendor
try { python -m miomedia.selftest } finally { Pop-Location }
```

含 `_native` 调用的 `suite.py` 不能只带旧的 12 文件包，必须同时提供 `_native/__init__.py`。新输入工具会拒绝这类缺文件包；检查与自检是两个独立步骤。

7. 做本机验收：

```powershell
flutter analyze --no-fatal-infos
flutter test --no-pub
python -m unittest discover -s tool -p test_miomedia_sdk_input.py
python -m unittest discover -s tool/source_runtime -p "test_*.py"
node --test tool/web_backend/runtime.test.cjs tool/web_backend/security.test.cjs tool/web_backend/parser.test.cjs
./tool/build-android.ps1
flutter build web --release --no-pub --no-wasm-dry-run
```

本机已有缓存时可以使用 `flutter pub get --offline --enforce-lockfile`；另一台机器第一次恢复时通常需要联网。不要复制旧机器生成的包路径 JSON 来代替恢复依赖。

环境文件和脚本仅影响当前终端及子进程，不修改系统 PATH 或其他项目。三个启动器 `build-android.ps1`、`start-web.ps1`、`start-home-preview.ps1` 在发现本机环境文件时会自动激活。新设备没有配置文件时仍保留原来的工具查找行为。退出终端即可结束会话环境。

## 4. 运行设备与开发电脑的区别

**Android 普通使用：** SDK 通过 Kotlin/Chaquopy 在 APK 内运行。手机不需要安装 Python、Node、JDK，也不使用电脑的项目目录。覆盖安装需要兼容签名；不要用清除应用数据的方式迁移路径。

**Web 本地开发：** 需要同一台电脑上的浏览器、Node 服务和 Python 服务。每个终端分别激活环境：

```powershell
# 终端一，保持运行
. ./tool/use-dev-env.ps1
python -B -X utf8 tool/source_runtime/server.py --port 8945
```

```powershell
# 终端二
. ./tool/start-web.ps1 -Port 8931 -RuntimePort 8945 -NoOpen
# 新版影视界面的独立开发预览入口：
# ./tool/start-home-preview.ps1 -Port 8933 -RuntimePort 8945 -Build
```

常规 Web 构建走 `lib/main.dart`，新版发现页预览走 `lib/main_home_preview.dart`，二者不是同一产物。发布 workflow 的 Web 附件目前只有静态构建，不包含 Node/Python 服务和私有 SDK，不能仅上传静态文件就期待内容接口正常。

**跨设备地址：** `127.0.0.1` 始终表示正在运行程序的那台设备。手机里的 `127.0.0.1` 不是电脑。默认 Node/Python 服务只监听电脑回环地址；当前服务也限制 Host/Origin，不能只把链接改成电脑局域网 IP 就作为多人部署。

安卓只有显式测试外部运行服务时才需要 `-RuntimeUrl` 与 USB `adb reverse`。默认内置模式不需要这些参数。正式远程部署还需独立处理 HTTPS、鉴权和每个用户/设备的会话隔离。

## 5. 持久数据与清理

- `flutter clean` 会清理生成文件。Web 默认身份在 `.dart_tool/miomedia/device.json`，使用前应备份；长期服务可用 `PLAYRA_MIOMEDIA_STATE_DIR` 指定独立持久目录。不要把它当成一般 Pub/Gradle 缓存删除。
- `.tooling/gradle/gradle.properties` 是每台电脑的资源设置，不随仓库同步。本机 JVM 原生内存不足后设置为 Gradle 堆 2 GiB、最多 2 个 worker、Kotlin 堆 768 MiB；其他设备按自身负载选择，不把这个值当作项目统一要求。
- `.tooling/dev-environment.json` 不含 SDK 密钥；私有 SDK、身份、签名文件和导出的 Secrets 分片分别保持在忽略位置。不要把整个 `.tooling` 或 `.dart_tool` 打包分享来代替安装说明。
- Git 同步代码与锁文件；通过受控私有方式分发授权 SDK 和签名材料。复制 APK/Web 构建时同时记录提交、版本、构建时间和 SHA-256。
- 历史文档中的 `C:/Users/...`、某台机器的 `build/releases`、备份目录和模拟器状态只是当时记录，不是新设备需要创建的固定路径。

## 6. 官方参考与本机记录

[Flutter 手动安装](https://docs.flutter.dev/install/manual)、[uv Python 存储目录](https://docs.astral.sh/uv/reference/storage/#python-versions)、[Playwright 浏览器目录](https://playwright.dev/docs/browsers)、[Chaquopy 资源打包](https://chaquo.com/chaquopy/doc/current/android.html#data-files)。Chaquopy 当前文档版本与项目固定的 17.0.0 不完全相同，实际构建版本以 `android/settings.gradle` 为准。

本次源代码/SDK 分析见 [Web、Android 与 SDK 分析](../analysis/web-android-sdk-20261013.zh.md)。本机安装、构建日志、原路径配置和 lock 备份保存在 `.tooling/dependency-setup-20261013` 与 `.tooling/logs`，这些目录不作为跨机器运行前提。

2026-10-13 本机验收：Flutter 528 项、Python 接入 44 项、SDK 输入 7 项、Node 11 项通过；SDK 两种自检通过；Web Release 与 Android Debug 构建成功。Android 包内已确认三种 ABI、Python 桥与表资源完整，尚未完成当前真机持续播放验收。此次源码修改未提交/推送，应用数据和正式签名未变。
