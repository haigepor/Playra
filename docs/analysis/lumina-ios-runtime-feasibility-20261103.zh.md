# Lumina 数据源在 iOS 的可运行性（代码级，2026-11-03）

结论：**按代码逻辑可以跑通，但当前代码在 iOS 上一行请求都发不出去。**
差的不是算法或协议，而是**四道打包门禁 + 一份 iOS 引擎产物**。
补齐后"认证头 → 请求加密 → 明文 HTTP → 响应解密 → JSON"这条链在代码层面是通的；
但本轮没有 Mac、没有 iOS 设备，**所有 iOS 运行时结论都属于推断 [HYP]，未验证**。

## 0. 一条决定性事实：请求与解密共用同一个 C 引擎

| 环节 | 调用 | 位置 |
|---|---|---|
| authentication 头 | `engine.auth(key, iv, a1)` → 112 B | `packages/lumina_engine/lib/client.dart:113-127` |
| 请求体加密 | `engine.encrypt(key, pad(...))` | `client.dart:132-145` |
| 响应解密（回落路径） | `engine.decrypt(key, cipher)` | `client.dart:139-165` |

即：**不存在"只发请求"或"只解密"的降级路径**——引擎不在，连 authentication 头都算不出来。
所以 iOS 的成败只取决于一件事：能不能拿到 iOS 的 `lumafuse` 引擎。

## 1. 分层判定

| 层 | iOS 结论 | 证据 | 阻塞 |
|---|---|---|---|
| 协议 / 密码学（RSA-2048、AES-128、自定义 base64、信封拆分、JSON） | 可用 | `primitives.dart:56`（纯 Dart AES）、`:183`（BigInt RSA）；`package:crypto` 纯 Dart | 否 |
| 网络（`dart:io HttpClient`、`Socket.startConnect`、DNS 过滤、8 s 超时） | 可用 | `client.dart:62-70`（连接工厂）、`:166-215`（请求/读取） | 否 |
| 明文 HTTP | 可用 | `ios/Runner/Info.plist:46-50` 已开 `NSAllowsArbitraryLoads`；`dart:io` 本身走 BSD socket 不经 ATS，两层都放行 | 否 |
| 文件 / 生命周期（`path_provider`、`File` 写入、gz 解压、`Isolate.spawn`） | 可用（未跑） | `lumina_executor_io.dart:96-158` | 否 |
| **原生引擎** | **不可用** | 无 iOS 产物 + hook 无 iOS 分支 + 资产不打包 + 平台开关不含 iOS | **是 ×4** |
| core 加速后端 | 自动关闭，回落 fuse | `core_backend.dart:47`（`supported` 只认 Android arm64）、`lumina_executor_io.dart:310` | 否 |

补充：`lumina_executor.dart` 用 `dart.library.io` 做条件导入，iOS 走的是真实现而不是 web stub，
所以只要放开开关，代码路径本身是通的。

## 2. 四道门禁（任意一道都足够让 Lumina 在 iOS 上不工作）

| # | 门禁 | 现状 | 最小改法 |
|---|---|---|---|
| 1 | 平台开关 | `lumina_support_io.dart:4-6` 只认 Android(arm64/x64) 与 Windows x64 → `discover_page.dart:52`、`content_providers.dart:8` 不注册来源，`lumina_executor_io.dart:27` 直接抛 `PLATFORM_UNSUPPORTED` | 增加 `Platform.isIOS && Abi.current() == Abi.iosArm64` |
| 2 | 资产打包 | `pubspec.yaml:173-177` 两项私有资产 `platforms: [android, windows]` → iOS 包内没有 `profile.json` / `fuse_image.bin.gz` | 追加 `ios` |
| 3 | build hook | `hook/build.dart:21-27` 的 `switch` 只有 Windows x64 与 Android arm64/x64，其余平台登记**空的 `LookupInProcess`** → `@Native(assetId: 'package:lumina_engine/engine')`（`lumina_engine.dart:6`）在 iOS 首次调用时符号解析失败 | 增加 `(OS.iOS, Architecture.arm64)` 分支，注册编译好的 dylib / 静态库 |
| 4 | 引擎产物 | 交付包只有 android arm64/x64、linux arm64/x64、macos arm64；**没有 iOS**。macOS dylib 的 `LC_BUILD_VERSION platform=macOS`，改名不能当 iOS 用 | 在 macOS + Xcode 上把 `jcy_engine_fuse.c` + `dll_iface.c` 重新编译为 `arm64-apple-ios` |

## 3. 为什么说"只差编译"，而不是"要重写"

1. 同一份 C 源码已经在 **6 个目标**构建过（Windows / Android arm64 / Android x64 / Linux arm64 / Linux x64 / macOS arm64），
   说明代码是平台中立的 C，不含 Linux/glibc 私有调用。
2. 源码在本机可用：`instruct/tv-reverse/workspace/com.tudou.tool/analysis/whitebox/src/jcy_engine_fuse.c`
   （3,415,796 B）+ 同目录 `dll_iface.c`。Playra 仓里只有二进制，没有源码。
3. 同仓已有 iOS 原生资产先例：`third_party/ech_http/hook/build.dart:20` 显式处理 `OS.iOS`，
   在 `:110-120` 用 `DynamicLoadingBundled()` 注册 `libech_*.dylib`，`ech_http` 的 `pubspec` 也声明了 `ios`。
4. `tool/cloud_build.py:16,143-147,230-231` 已支持 `ios`（`macos-15` runner，`flutter build ios --no-codesign`），
   只是从未跑过。

## 4. 补齐后仍未验证的点（全部 [HYP]，附验证动作）

| # | 风险 | 为什么担心 | 验证动作 |
|---|---|---|---|
| 1 | dylib 的嵌入与签名 | iOS 上 `dlopen` 需要库在 `Runner.app/Frameworks` 内且签名有效；`DynamicLoadingBundled` 在 iOS 的具体落位未在本仓验证 | `unzip -l Runner.app \| grep lumafuse`；`codesign -dv --verbose=4 Runner.app` |
| 2 | 内存峰值 | 87.6 MB 运行时镜像 + 解压副本 + 4 路 Cb 标定缓存，老机型可能触发 jetsam | Instruments / `os_proc_available_memory`，冷启与首播各观察一次 |
| 3 | DNS / IPv6 选路 | `client.dart:70` 取 `addresses.first`，若首选 IPv6 而网络不通会整条请求失败 | 强制 IPv4 与默认各跑一轮七操作 |
| 4 | 首次冷启耗时 | Android 实测首调 ~5.5 s（引擎初始化 + 首次标定），iOS 是否同量级未知 | 冷启计时，判据 < 8 s |
| 5 | 上架合规 | `NSAllowsArbitraryLoads` 需要审核说明；响应私钥打进 IPA 与 Android 现状同级 | 产品决策，不在本轮 |

## 5. 如果不想改代码：服务端 BFF

iOS 端不碰引擎、不装私钥，走自建 HTTPS 接口，服务端跑现有 SDK（Python/Dart 均可）。
代价是多一跳网络与服务端成本；好处是 Web/iOS/桌面共用一套，且不用回答"私钥为什么在客户端"。

## 6. Mac 上的验证清单（本轮 NOT RUN）

```bash
# 1) 编译（源码取自 tv-reverse whitebox）
clang -target arm64-apple-ios13.0 -fPIC -O2 -shared \
      -o liblumafuse_ios_arm64.dylib jcy_engine_fuse.c dll_iface.c
nm -gU liblumafuse_ios_arm64.dylib | grep -c lumafuse_        # 期望 21

# 2) 接线后构建
python tool/cloud_build.py build --platform ios              # --no-codesign
# 3) 产物检查
unzip -l build/ios/iphoneos/Runner.app | grep -E 'lumafuse|lumina_private'
# 4) 七操作（同一份代码）
dart run packages/lumina_engine/bin/live.dart <profile.json> <image.bin> <report.json>
```

判据：`live.dart` 七操作全 PASS 且 `mediaProbe` 返回 206；App 内首页能出目录、详情能起播。

## 7. 边界

- 本文只做**代码与产物层**推断，没有在 iOS、macOS 或 Xcode 上执行任何构建或运行。
- Android 侧结论来自 2026-11-03 真机（`docs/analysis/lumina-source-sync-20261103.zh.md` §5），
  不能直接外推到 iOS。
- 平台总表见 `docs/analysis/lumina-platform-matrix-20261103.zh.md`；本文是其中 iOS 一行的代码级展开。
