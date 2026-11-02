# Lumina 原生依赖与跨端架构核验

> 执行状态已更新：当前代码采用 Dart + C，旧 Python 链已退役；以 [原生迁移验收](../verification/lumina-native-reset-20261019.zh.md) 为准。下文保留执行前的分析与范围依据。

核验日期：2026-10-19。依据新 SDK `88109b2` 加本轮边界修复、Playra 当前工作区及本机依赖隔离试验。本文区分现状与建议；没有实施 Dart 协议迁移，也没有生成 iOS 引擎。

## 结论

**不需要把 Android 设备桥作为产品依赖；可以不使用官方 `libcore.so`，由 SDK 自带的 `_fuse` 完成正常请求、鉴权和响应解密。但当前完整 SDK 仍需要本地原生引擎及运行时镜像，并非纯 Python/Dart、无原生产物的算法包。**

“C 语言实现”与“跨平台”并不冲突：同一引擎按目标系统、CPU 和 ABI 编译为不同产物。跨端的障碍是缺少部分平台产物，以及 Playra 当前只有 Android 内嵌了 Python 宿主；不是所有端都必须连接 Android 设备。

## 三种容易混淆的依赖

| 名称 | 实际职责 | 是否要求独立 Android 设备/桥进程 | 当前接入中的地位 |
|---|---|---|---|
| `_device` / `core_serve` | 经 TCP 调用设备进程中的官方库，adb 转发是调试部署方式之一 | 是，要求可达的设备侧服务 | 可选且默认关闭；Playra 导入白名单不含 `_device` 与桥程序 |
| `_soloader` / 官方 `libcore.so` | 在当前进程加载官方库，异步回调取得响应明文 | 不需要独立桥进程 | ARM64 响应解密可选路径；不可用时回到 `_fuse`；不是请求/鉴权的替代实现 |
| `_fuse` / `liblumafuse` | 通过 C 转译引擎运行块密码、鉴权管线、标定与 C 解密核 | 不需要 Android 设备 | 当前完整业务链的基础依赖；按平台交付 DLL/SO/dylib，并需要 `fuse_image.bin` |

Flutter 的 `MethodChannel → Kotlin → Chaquopy` 是应用内部宿主桥，也不是 `_device` 设备桥。更换算法执行后端不会自动消除这个 Python 宿主层。

源码依据：新 SDK `sdk/python/lumina/_fuse/__init__.py`、`_device/__init__.py`、`_soloader/__init__.py`；项目 `tool/source_runtime/import_lumina.py` 与 `lumina_adapter.py`。

## 算法到底完成到了哪一层

```text
鉴权头 → auth.generate_auth → block.backend_auth_pipeline → _fuse.auth_pipeline

请求体 → envelope.build_request_envelope
       → RSA 公钥封装 + EBlock.encrypt → 标定/加密引擎 _fuse

响应体 → envelope.open_response_envelope
       ├─ _soloader：本进程官方库直接解密（可选）
       ├─ _device：独立设备桥（可选，Playra 没有导入）
       └─ RSA 私钥解封
          ├─ ljc + 匹配且足量的 CbTable + 引擎提供的 C(K)/CONST_1
          └─ EBlock.calibrate → _fuse.calibrate_direct → C 解密核

播放解析器 → play.py / aes_cbc.py → 直链与请求头 → 现有播放器
```

SDK 已把可调用的完整业务链封装好，但各部分分布在 Python、C 引擎和数据资产中。RSA/DER、CB64、协议 JSON、信封编排、HTTP Client、播放解析器主要仍由 Python 实现。`_fuse` 暴露的是密码/标定等 C ABI，并没有让整个 Python `Client` 自动变成一个 Dart 可直接调用的完整 C SDK。

`ljc.py` 的解密公式需要每个密钥对应的 `C(K)`、`CONST_1(K)`、`Cb_b(K)`。当前 `C_of_K` 和 `CONST_1_from` 首次计算仍调用引擎；11 份随包表各覆盖 84 块，只覆盖特定密钥和长度。`CbQuery` 也调用 `_fuse.calibrate_direct`，并不会消除引擎依赖。实际响应路由目前只尝试 `CbTable`，没有接入 `CbQuery`。

因此，“解密公式已经还原”不能推导出“任意新密钥、任意长度、没有引擎也能计算”。这描述的是当前实现能力，不是对未来能否进一步还原算法的数学断言。

SDK 文档称引擎由构建期生成的 C 源编译，约 8 万行；**当前交付目录没有该引擎源码或头文件**。目录中的两个 C 文件是设备桥/直载验证工具，不是可供重新编译各平台引擎的源码。现有预编译产物可以使用；新增平台需要交付方补产物，或提供可复现的引擎构建输入。

## 依赖隔离的实际验证

Windows x64 当前导入副本，关闭 `LUMINA_SOLOADER`，无 `_device` 模块：

| 检查 | 结果 |
|---|---|
| `_fuse.available()` / 版本 | `True` / `lumafuse-1.6` |
| 随机新密钥加密后解密 | 明文逐字节一致 |
| 鉴权生成、请求信封生成 | 均成功，无设备桥 |
| 隔离 `_fuse/_native/_emu` 后生成鉴权 | 明确抛出 `RuntimeError` |
| 隔离全部引擎后生成请求信封 | 明确抛出 `RuntimeError` |
| 已知表内密钥首次计算 `C(K)`，但没有引擎 | 明确抛出 `RuntimeError` |

原始脱敏结果：`.dart_tool/lumina-upgrade-20261019/cross-platform-dependency-probe.json`。SDK 的“零第三方依赖”是 Python 安装依赖层面的描述，不表示没有随包本地二进制。

原生头检查：官方 `libcore.so` 是 ELF64/AArch64，依赖 Android 的 `liblog.so` 等库，不能当成通用 Windows/Linux/iOS 动态库直接使用。SDK 的 `_fuse` 才提供各平台独立产物。

## SDK 具备产物，不等于 Playra 已在该端本地接入

| 目标 | SDK 本地引擎交付 | Playra 当前使用方式 | 当前缺口 |
|---|---|---|---|
| Android ARM64 | `_fuse` SO；另有官方 ARM64 `libcore.so` | Chaquopy 内嵌 Python，默认尝试官方直载响应路径 | 两种后端及实际播放已验收；雷电含 ARM 指令翻译，不能替代 ARM 真机性能 |
| Android x86_64 | `_fuse` SO | Chaquopy 内嵌 Python；无对应官方库，走 `_fuse` | 不需要设备桥；本轮已有实际播放与固定密文测量 |
| Android ARM32 | 无对应 `_fuse` | 不登记 Lumina | 不能靠开关补出缺失引擎 |
| Windows x64 | `fuse_core.dll` | APP 使用配置的算法服务地址；服务可在本机运行 | 桌面 APP 没有随包启动 Python/引擎的自动生命周期管理 |
| Linux x64/ARM64 | 独立 Linux SO | 同上 | 同上，另需在目标环境验收 |
| macOS ARM64 | macOS dylib | 同上 | 同上，另需签名与目标环境验收 |
| macOS Intel / Windows ARM64 原生 | 无对应产物 | 可使用受控服务 | 模拟/翻译不计入原生支持承诺 |
| iOS | 无 iOS `.a` / framework / XCFramework | 当前 `luminaSupported` 显式为 false，隐藏 Lumina | iOS 引擎产物、客户端宿主/协议层及设备验收均缺失 |
| Web | 浏览器不能直接消费现有 DLL/SO | 同源 BFF → Python 算法服务 | 现有引擎不是 WASM；不能直接改成前端加载 |

macOS ARM64 dylib 与 iOS ARM64 库不是同一个平台产物；不能改名复用。桌面有服务地址才显示 Lumina，也不能等价为服务已部署健康。

## 面向跨端的建议

**近期升级继续保留现有七项业务契约，以 `_fuse` 作为可跨平台交付的共同基础，把官方直载定位为 Android ARM64 的可选优化。** 不引入 `_device`、adb 或独立设备桥作为安装前提；本轮没有擅自删除原已批准的直载能力。

若目标是所有 Native 客户端独立运行，长期边界应为：

```text
Flutter 页面 / 当前作品、线路、集数和播放模型
                  ↓ 七项 Lumina 业务操作
           共用 Dart 协议与网络执行层
                  ↓ 一次完成批量密码操作的 C ABI
       Windows DLL / Android SO / Linux SO / Apple 原生产物

Web 页面 → 同源 BFF → 共用契约的服务端实现
```

这条方向由当前 Flutter/Dart 的 C FFI 能力支持；各平台依然需要独立的编译、打包和加载方式，iOS 可以静态链接后查找进程符号。它不是简单删除 Python import：还需要迁移鉴权、信封/RSA/CB64、播放解析、异常边界、持久身份、缓存和取消语义，并与当前 SDK 固定向量及真实响应对拍。

先取得引擎头文件、稳定 C ABI、版本/资产摘要及 iOS 设备/模拟器产物，再做一条七项业务共享实现；避免先分别维护 Android、iOS、桌面三份密码算法。无须为“去 Python”从规格重新猜实现 C(K)/Cb 的生成器。当前 Windows 环境不能完成 iOS 原生编译与真机验收。

桌面也可先交付受管理的本地 Python 服务进程，复用 SDK 降低迁移量；该路线仍有解释器、进程启动与生命周期成本。若目标是不依赖额外服务和 Python，Dart + C 引擎才是相应的迁移目标。迁移 Lumina 不会自动移除仍供其他 SDK 使用的 Chaquopy。

## 加载与性能影响

- 移除设备桥的 IPC 对当前 Playra 没有直接提速收益，因为桥模块本来就没有导入。
- 原生 C 已承担重要计算，但新密钥的引擎标定仍有成本；不能把“解密核是 C”解释成整个请求接近零耗时。
- `_fuse` 为进程级共享状态，Python 包通过 `RLock` 串行化原生调用。4 个宿主工作线程不等于 4 个引擎并行计算。未来 Dart 工作 isolate 也必须保留正确的串行或独立上下文机制。
- 本轮最终雷电 x86_64、2905 字节同一份配置响应，20 次热态 `_fuse` 解密 p50 428.226ms、p95 521.117ms。它是特定设备/密文样本，不是所有端或升级速度比例；网络、标定、解析器与播放器首帧应继续拆开测量。
- `fuse_image.bin.gz` 为 3,719,655 字节，解压为 87,642,260 字节（约 83.6MiB）。这是磁盘数据大小，不是实测 RSS；冷启动解压、初始化与内存峰值仍应单独测量。
- 当前官方 ARM64 库 LOAD 对齐为 4KiB，两个 Android `_fuse` 库为 16KiB；不能由其中两个库推导整个 APK 已通过 16KiB 设备验收。

## 核验范围与当前实施状态

本轮升级已在工作区完成边界修复、v3 导入/摘要、构建输入与诊断接入，以及下述雷电分 ABI 验收。雷电 ARM64 进程实际报告 `armv8` 且指针为 8 字节，为 SDK 和宿主登记补带 64 位检查的兼容及回归后，七类操作通过 `_fuse` 跑通，且设备身份文件摘要与此前 x86_64 一致。

进一步原生探测确认官方库可加载、初始化，`get_version` 实际返回 `{'action': None, 'code': 200, 'payload': {'version': 51}}`。原 SDK 只提取业务 `payload.data`，因此把版本回复误判为失败，令 `available()` 返回 false。已在源 SDK 增加仅限版本动作的解码及业务/错误分支回归，重新导入并构建验证。这是兼容问题，不能把它当作 ARM64 官方库不能加载的证据。

修复后 ARM64 七类接口全部成功，实际响应路径为 `soloader`；同设备同一份 2905 字节响应，两后端各 20 次热态解密明文字节一致：`fuse-eblock` p50/p95 为 **954.429/1154.515ms**，`soloader` 为 **38.161/61.789ms**。这说明保留 ARM64 可选加速路径有实际价值，但它不是跨端共同前提；此样本包含 Houdini 指令翻译，且只度量解密，不能作为整个应用的升级提速比例。

现有历史文档 `lumina-ios-local-feasibility-20261016.zh.md` 的“暂停 iOS 研究”属于当时状态，本次按用户新要求重新核验跨端，缺失产物的事实仍成立。

本次分析不改变平台开放范围或业务协议。升级文件与原始 SDK/APK 的备份在 `.dart_tool/lumina-upgrade-20261019/backup/`，源目录修复仍先在 SDK 源目录实施后导入。完整变更、验收和回滚见 [升级验收记录](../verification/lumina-upgrade-20261019.zh.md)；最终已在雷电安装关闭诊断的 x86_64 日常测试包。

官方参考（当日已核验）：[Dart C interop](https://dart.dev/interop/c-interop)、[Flutter 原生 FFI 链接方式](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin)、[Chaquopy Android Gradle 插件](https://chaquo.com/chaquopy/doc/current/android.html)。SDK 自身的平台和源码交付边界见其 `docs/sdk/python.md`“引擎后端”章节，算法标定边界见 `docs/reference/block-cipher.md`。
