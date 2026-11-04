# Lumina 数据源跨端可用性核验（2026-11-03）

结论先行：**Android 可用（已真机验证）；iOS 当前不可用但可移植；Web 当前不可用，且浏览器内直连在协议层就过不去 —— 只能走服务端 BFF。**

本文只回答"这个数据源能不能在 Web / iOS 正常发请求"，不涉及 UI 移植与播放器适配的完整验收。

## 1. 四层门禁（任何一层不过，该平台就发不出请求）

| 层 | 机制 | 位置 |
|---|---|---|
| 编译期 | `dart:ffi` / `dart:io` 是硬依赖；Web 无 FFI、无 `HttpClient` | `packages/lumina_engine/lib/lumina_engine.dart:1`、`lib/client.dart:3,78` |
| 条件导入 | Web 落到 stub，`executeLumina` 直接抛 `PLATFORM_UNSUPPORTED` | `lib/services/source/lumina/lumina_executor.dart:2`、`lumina_executor_stub.dart` |
| 平台开关 | `luminaSupported` 只认 Android(arm64/x64) 与 Windows x64 | `lib/services/platform/lumina_support_io.dart:4` |
| 资产 gate | `profile.json` / `fuse_image.bin.gz` 只对 android/windows 打包 | `pubspec.yaml:173-177` |
| 原生产物 | build hook 只映射 Windows x64 + Android arm64/x64；其余平台登记空 `LookupInProcess` | `packages/lumina_engine/hook/build.dart:20-45` |
| 网络 | 服务端只有明文 HTTP `43.145.33.254:27990`，无 CORS | 见 §3 实测 |

## 2. Web：不可用（且不只是"没打包"）

### 2.1 当前代码层面

- `lumina_engine` 包整体不可用于 Web：`dart:ffi` 在 web 目标不存在，`@Native(assetId:)` 无法解析。
- `client.dart` 用 `dart:io` 的 `HttpClient`，Web 没有这个库。
- 因此仓库用条件导入把 Web 指向 stub（`PLATFORM_UNSUPPORTED`），并在 `luminaSupported` 处把整条链路关掉。
- 资产按平台打包，Web 包内**不存在** `lumina_private/`，响应私钥不会进浏览器 —— 这一点是刻意设计的，不是遗漏。

### 2.2 实测（2026-11-03，当前工作树）

```bash
flutter build web --release --no-web-resources-cdn --dart-define=PLAYRA_DIAGNOSTICS=false
# → √ Built build/web（74 s；WASM dry-run 因 media_kit/dart:ffi 直接不通过）
```

产物检查：

| 检查项 | 结果 |
|---|---|
| `build/web/assets/assets/lumina_private/` | 不存在 |
| `main.dart.js` 中 `lumafuse` / `lumina_private` / `lumina_engine` | 0 次 |
| `PLATFORM_UNSUPPORTED` 字样 | 0 次（分支被树摇） |
| `profile.json` 私钥片段是否出现在 bundle | 否 |
| 残留的 `lumina` 字样（48 处） | 仅为 UI/模型字符串（"动漫 · Lumina"、"当前平台尚不支持 Lumina" 等），不含引擎路径 |

即：**Web 包能构建、能跑，但 Lumina 这条源在编译进产物时就已经不在了。**

### 2.3 网络层：浏览器直连的硬阻塞（实测）

```text
GET  http://43.145.33.254:27990/app/config   → 200，响应头无 Access-Control-Allow-Origin
OPTIONS 同路径（预检）                        → 404，无 CORS 头
https://43.145.33.254:27990/                 → 连接失败（code 000，该端口不提供 TLS）
PARSER_URL = http://yh.jx.hzhcbkj.cn/...      → 同样是明文 HTTP
```

三条独立阻塞：

1. **混合内容**：任何 HTTPS 页面调用 `http://` 接口都会被浏览器拦掉；
2. **CORS**：即便页面跑在 HTTP 下，`fetch` 也读不到响应（无 ACAO、无预检支持）；
3. **私钥**：响应解密需要 `profile.json` 里的 RSA 私钥，放进前端等于公开。

结论：**Web 端只能做 BFF** —— 服务端跑现有 SDK（Python/Dart 均可），浏览器只调你自己的 HTTPS 接口。
WASM 路线不成立：引擎是 114K 行 C 转译产物 + 87 MB 运行时镜像，且 Dart Web 没有 FFI，
需要整包改写为 JS interop；`media_kit` 自身连 WASM dry-run 都过不了。

## 3. iOS：当前不可用，但可移植

> 代码级逐层判定（请求/解密共用一个 C 引擎、四道门禁、运行时风险、Mac 验证清单）见
> `docs/analysis/lumina-ios-runtime-feasibility-20261103.zh.md`。本节只给现状与改造面。

### 3.1 现状（为什么现在不行）

| 项 | 现状 |
|---|---|
| 平台开关 | `luminaSupported` 不含 iOS → 源不登记，UI 不显示 |
| 资产 | `pubspec.yaml` 只对 android/windows 打包 → iOS 包里没有 profile/image |
| 原生产物 | `packages/lumina_engine/native/` 只有 Windows DLL 与两个 Android .so，**没有 iOS 的 .a/.dylib** |
| build hook | `switch` 无 iOS 分支 → 登记空 `LookupInProcess`，即便放开开关也会在首次 `@Native` 解析时失败 |
| 交付包产物 | `deliver/engine/` 有 6 平台（win/android×2/linux×2/macos），**无 iOS**；macOS dylib 的 `LC_BUILD_VERSION platform=macOS`，不能改名当 iOS 用（见 `lumina-ios-local-feasibility-20261016`） |
| CI | `tool/cloud_build.py` 支持 `flutter build ios --no-codesign`，但近期 run 全部是 android/web，**iOS 目标从未跑过** |

### 3.2 可移植性（为什么说"可做"）

- 协议层已经全部在 Dart 里，与平台无关；iOS 有 `dart:io` 与 `dart:ffi`。
- 引擎 C 源码在仓库内：
  `workspace/com.tudou.tool/analysis/whitebox/src/jcy_engine_fuse.c`（3,415,796 B，约 114K 行）
  + `dll_iface.c`（Android so 实测 **21 个 `lumafuse_*` 导出**），已在 Windows / Android / Linux / macOS 六目标编译过 ——
  说明代码是平台中立的 C，iOS 需要的是重新编译，不是重写算法。
- 同一仓库里已有 iOS 原生资产的先例：`third_party/ech_http/hook/build.dart` 显式处理 `OS.iOS`。

### 3.3 改造清单（按依赖顺序）

1. 在 macOS + Xcode 上把 `jcy_engine_fuse.c` + `dll_iface.c` 编译成 `arm64-apple-ios13.0` 的静态库
   （`.a`，链接进 Runner）或动态 framework；用 `nm` 核对 21 个 `lumafuse_*` 导出；
2. `hook/build.dart` 增加 `(OS.iOS, Architecture.arm64)` 映射，产物以 `LookupInProcess`（静态链接）
   或 `DynamicLoadingBundled`（framework）交付；
3. `pubspec.yaml` 的两项私有资产 `platforms` 追加 `ios`；
4. `lumina_support_io.dart` 增加 `Abi.iosArm64`；
5. 真机验收：`bin/check.dart`（离线向量）→ `bin/live.dart`（七操作）→ UI 起播。

风险与代价：

- 解压后的运行时镜像 87.6 MB，iOS 内存压力与首启解压时间需实测（Android 上冷启首调 ~5.5 s 可参照）；
- core 加速后端（供应商 `libcore.so`）是 Android arm64 专有，**iOS 只能用 fuse 引擎**，
  按本次实测吞吐约 60–70 ms/KB；
- App Store：固定引擎本身不违反"动态代码"条款，但把响应私钥打进 IPA 是产品级风险（与 Android 现状同级）；
- 本机是 Windows，没有 Xcode/iOS SDK —— 这一步必须在 Mac 上做，本轮无法代跑。

## 4. 顺带发现：Linux / macOS 其实是"差接线"

交付包已有 `liblumafuse_linux_{arm64,x64}.so.gz` 与 `liblumafuse_macos_arm64.dylib.gz`，
但 Playra 的 build hook 只映射 Windows 与 Android，`luminaSupported` 也只认这两个 →
Linux/macOS 现在和 iOS 一样是关的，尽管产物已经存在。接这两个平台是纯机械改动
（hook 加映射 + 资产 platform + ABI 判断），比 iOS 便宜得多。

## 5. 平台矩阵

| 平台 | 能否发请求 | 依据 | 缺什么 |
|---|---|---|---|
| Android | ✅ 可用 | 真机 4K 起播 + 七操作 7/7（2026-11-03） | — |
| Windows | ✅ 代码与产物就绪 | hook 映射 + x64 DLL；本轮未实测 | 一次真机冒烟 |
| Linux / macOS | ❌ 当前关闭 | 有 .so/.dylib，hook 与开关未接 | 接线（0.5 天级） |
| iOS | ❌ 当前关闭 | 无 iOS 产物、开关不含 iOS | 重新编译 + 接线（Mac 上 1–2 天） |
| Web | ❌ 设计上不支持 | stub + 资产 gate + HTTP 无 CORS | 只能做服务端 BFF |

## 6. 复现

```bash
# Web 构建与产物检查
flutter build web --release --no-web-resources-cdn
ls build/web/assets/assets/lumina_private        # 应不存在
grep -c "lumafuse\|lumina_private" build/web/main.dart.js   # 0

# 网络门禁
curl -s -o /dev/null -D - -H 'Origin: https://example.com' http://43.145.33.254:27990/app/config
curl -s -o /dev/null -D - -X OPTIONS http://43.145.33.254:27990/app/config
curl -s -o /dev/null -w '%{http_code}\n' -k https://43.145.33.254:27990/   # 000

# iOS（需 macOS）
grep -n "OS.iOS" third_party/ech_http/hook/build.dart     # 先例
grep -n "switch ((code.targetOS" -A 6 packages/lumina_engine/hook/build.dart  # 现无 iOS 分支
```
