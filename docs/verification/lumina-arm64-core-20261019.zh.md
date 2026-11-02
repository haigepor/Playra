# Lumina ARM64 C 后端、播放失败修复与布局验收

日期：2026-10-19。项目目录 `D:/project/Playra`；SDK 基线 `88109b2`。

## 已确认的失败原因

本次 ARM64 首包能初始化供应商 `libcore`（版本 51），但播放失败。原因是新接入将 `/app/video/play` 交给 `api_decrypt`，遗漏了实际 HTTP 请求中的 `id`、`play`、`part` 查询参数。SDK 原实现将包含查询串的路径传给响应解密。

使用同一份真实响应重放，结果如下：

| 密文 / 上下文 | `_fuse` | 进程内 C |
|---|---|---|
| 配置响应，`/app/config` | 业务码 20000 | 业务码 20000，JSON 内容一致 |
| 播放响应，只传路径 | 业务码 20000 | 业务码 300400，访问控制，errCode 10032 |
| 同一播放响应，传完整原始查询路径 | 业务码 20000 | 业务码 20000，JSON 内容一致 |

该重放没有修改密文、供应商库或访问控制规则。修复保留请求的查询串及原编码；真正的业务拒绝继续向上传递，不会为了得到成功结果而切换解码器。

页面还有一项独立误报：画质查询异常后，手动画质候选为空，被直接归类为 `QUALITY_UNAVAILABLE`。修复后会保留用户明确选择的档位，让实际播放解析验证；真实已知档位缺失仍返回不可用，不静默升降档、不切换已锁线路。

## C 接入边界

- 保持 Dart + C：Dart 负责 HTTP、鉴权组装、RSA、业务转换和解析器；C 负责既有专用算法，以及 ARM64 官方库响应解密。
- 新增本项目适配 ABI 1：`include/lumina_core.h`、`src/lumina_core_shim.c`。这不是供应商正式头文件。
- 仅绑定 SDK 已验证的 `init`、`call` 和三个 AES 导出。初始化 JSON 由适配层复制并持有到进程退出。
- 原生线程接收回调，复制有界响应；Dart 不从原生线程接收回调。通过 `lumina_core_free` 释放返回缓冲。
- 原生调用串行，排队与执行共用超时预算。执行超时后永久隔离本进程中的该后端，迟到回调不能进入下一次请求；进程重启后重新探测。Dart 请求取消不能中止已经开始的供应商执行。
- 普通模式下，已识别的原生加载/执行故障可回到 `_fuse`，仍受剩余请求预算约束。严格诊断模式不静默回退。
- x86_64 与 Windows 继续使用 `_fuse`；Android ARM32 不登记 Lumina；iOS 尚缺供应商产物，未启用 Lumina。
- 库从应用打包的只读原生目录加载，应用数据目录仅保存数据与原安装设备身份。没有恢复 Python、Chaquopy、设备桥或独立解密服务。

构建采用 Flutter code assets 和 NDK 编译适配层；相关官方说明：[Dart C interop](https://dart.dev/interop/c-interop)、[Android NDK 编译器目标](https://developer.android.com/ndk/guides/other_build_systems)。

## 界面调整

- 保留现有深色主题，将来源、线路与画质合并到一个播放设置面板。
- 单一来源使用轻量文字；收藏、线路入口和真实画质选项保持可操作。
- 错误提示使用紧凑侧边强调条，文字与重试同行，多线路恢复操作收进菜单。
- 画质异常与播放异常避免重复显示；独立画质加载失败提供重新获取动作。
- 窄屏和大字号允许自然换行，保持恢复操作的触控区域，不固定错误卡片高度。

正式包界面：[雷电 720×1280 截图](lumina-arm64-player-20261019.png)。

## 验证记录

- 722 项完整 Flutter 回归通过，包含历史身份、Bangumi、播放编排、画质偏好、窄屏与大字号。
- 最后收紧画质行和面板间距后，55 项相关定向回归再次通过；11 组块加解密向量、3 组鉴权向量及 8 项协议/原生检查通过。
- 两项误报回归先复现失败，再通过修复：查询失败不能冒充档位缺失；真实响应错误不能被 `QUALITY_UNAVAILABLE` 覆盖。
- C 契约 10 项在雷电分别以 x86_64 和 ARM64 通过：正常、库缺失、AES 自检失败、迟到回调、阻塞调用、无回调、并发、排队预算、损坏 base64、错误 padding。
- 私有输入验证及三项恢复边界测试通过。
- 最终正式 APK 核对为 ARM64 单 ABI，三份库和私有资产摘要匹配，Python/Chaquopy 条目为零。
- 覆盖安装版本号 24308，包名和签名沿用原安装；`firstInstallTime=2026-10-13 17:35:25` 保持不变。没有卸载或清除应用数据。
- 正式包在雷电覆盖安装成功，`primaryCpuAbi=arm64-v8a`；首页和《来自远方》详情正常，显示 4K / 1080p，未再出现截图中的画质误报。正式包忽略预先设置的诊断 `fuse` 选择文件，日志中没有诊断事件；复核后删除该测试选择文件。
- 正式包实际显示 3840×2160 视频，续播位置从 4:49 推进到 5:04，已人工查看画面与播放控制。初始画面出现后仍经历缓冲，未把尺寸回调或单张画面当作持续播放流畅的证明。

## 性能采样口径

雷电为 Android 14、x86_64 宿主，通过 Houdini 执行 ARM64 应用，页面大小 4 KiB。结果不能替代 ARM64 真机数据。

同一 ARM64 诊断 APK 分别强制 `fuse` 和 `core`；应用重启后切换，检查实际后端及回退事件。采样期间不运行宿主构建或回归测试。

- `core_initialize`：供应商加载、自检、初始化及版本探测。
- `request_encrypt`：POST 信封构建；此阶段仍使用既有 C 引擎，不能计入 HTTP。
- `initial_line_ready`：从详情资料加载开始，到首次真实播放材料就绪，包含首次目录与画质探测。
- `line_ready`：本次播放/换画质调用开始，到地址就绪；已有材料命中不能被当作首次解析。
- `video_first_frame.ms`：沿用历史事件名，实际为 mediaKit 的首帧 Future 完成通知；当前 Android 实现也会在收到视频尺寸时完成它，因此它只是播放器就绪代理，不能当作画面已显示。`selectionMs` 包含此次选集/换画质的解析准备。
- HTTP、解密、解析器及队列单独记录。日志异步输出，不以 logcat 输出时刻推算端到端耗时。

同密文二十轮对照（ARM64 release 独立验收包，2,885 字节真实详情信封；包含 RSA / JSON 处理，不含 HTTP）：

| 路径 | p50 | p95 | 样本 |
|---|---:|---:|---:|
| `_fuse`，每次清除标定缓存 | 2,466.979 ms | 3,163.445 ms | 20 |
| `_fuse`，同 K 命中标定缓存 | 20.940 ms | 36.101 ms | 20 |
| 进程内 `core` 热态 | 123.934 ms | 171.888 ms | 20 |

全部样本的业务 JSON 内容一致。`core` 的进程冷初始化为 189.501 ms。该固定密文对照不等于完整播放加速比例；真实响应通常使用新 K，换画质则优先复用 27 秒内的上层材料缓存，不应重复解密。

七类真实接口全部通过且记录实际后端为 `core`。两轮功能样本中，完整播放操作分别约 725 ms 和 2,305 ms，说明网络、请求加密和解析器仍会影响端到端耗时，不能预设固定的亚秒结果。最新完整 20 轮原始样本保存在私有审计目录和备份目录的 `arm64-core-benchmark.json`；独立入口将完整报告写到应用 external-files 的同名文件，避免 Android 长日志截断。

页面实测使用同一份 ARM64 诊断 APK、同作品《来自远方》、同一第 3 集；各重启一次强制 `core` / `fuse`。这是少量真实功能样本，不是端到端分位数：

| 阶段 | `_fuse` | `core` |
|---|---:|---:|
| 从详情加载到首次材料就绪 | 13,327 ms | 1,516 ms |
| 素材过期后重新解析 4K 到地址就绪 | 8,682 ms | 1,894 ms |
| 缓存命中，切到 1080p / 4K 到地址就绪 | 8 / 21 ms | 6 / 13 ms |
| 播放器装入到库回调代理，1080p 样本 | 2,459 ms | 3,174 ms |
| 缓存换画质，选择动作到库回调代理，1080p / 4K | 1,860 / 2,239 ms | 4,599 / 2,130 ms |

两种后端的缓存换画质都没有新增接口或解密。以上回调不能证明真正的可见首帧。检查当前 mediaKit Android 源码，`videoParams` / `SetSurfaceSize` 与实际 `notifyFirstFrameRendered` 共用该 Future；尺寸先到时，通知会早于画面出现。

为补充可见画面证据，另用开发工具连续读取雷电 720×1280 RGBA 截图，观察视频区域先变暗、再连续两次出现明亮内容，并人工检查最终截图。每次截图本身约需 1–2 秒，以下是粗粒度采集区间或上界，不是 VSYNC 时间，也不是首帧 p50/p95。海报、旧画面不能直接触发成功。

| 外部画面采样 | `_fuse`：点击到可见内容上界 | `core`：可见内容采集区间 |
|---|---:|---:|
| 已准备材料，首次点播放 4K | 约 12.5 秒 | 约 4.5–7.5 秒 |
| 缓存内切到 1080p | 约 9.0 秒 | 约 3.6–6.7 秒 |
| 切回 4K，材料已过期 | 约 20.3 秒 | 约 5.1–7.5 秒 |

第三次操作包含重新解析：`fuse` 地址就绪约 12.9 秒，`core` 约 1.1 秒，不能归类为缓存切换。前两次均复用材料，画面时间差不能归因于 C 解密。画面出现后仍可能继续缓冲；真实可见内容明显晚于库回调，剩余瓶颈包含媒体/CDN、续播定位及播放器执行。外部采集也会扰动模拟器，需真机与精确渲染埋点进一步量化。

外部记录为 `fuse-visible-visible.json`、`core-visible-visible.json` 和对应截图；`tool/measure-lumina-visible-frame.cjs` 仅为开发采集工具，其三项门限测试通过，不是应用运行依赖或设备解密桥。

首次 `core` 材料准备中的播放阶段：请求信封加密 515.704 ms，上游 HTTP 57.758 ms，响应解密 268.043 ms，解析器 HTTP 241.908 ms。一次后续解析的解析器 HTTP 为 1,429.332 ms，说明外部等待也有明显波动。

`fuse` 首次首页目录请求出现过 30 秒截止超时：频道解密约 3.69 秒，banner 约 8.57 秒，目录约 26.27 秒；详情对照通过保留的历史入口完成，未把首页导航等待计入详情内部计时。记录中快速点选造成的取消样本未计入成功首帧比较。

实际页面已观察到 1920×1080 与 3840×2160 解码尺寸及视频画面。正常播放会更新该集的观看进度，应用数据、历史身份和收藏没有清除。

主要证据：私有审计目录的 `fixed-core-complete.json`、`fixed-fuse-real-ready.json`、`fixed-fuse-controlled.json`；均只含阶段、耗时、质量代号和错误码，不含密钥或媒体地址。

## 私有构建输入、文件与回滚

`inputs.json` 接入版本升级至 2，纳入官方 ARM64 库及通道配置摘要。供应商库 SHA-256：`26727c7b68308d3055860a71aa0c217380319ba22bc99cfb425c12e3d4e84f17`。

| 文件组 | 用途 / 影响 |
|---|---|
| `packages/lumina_engine/include/lumina_core.h`、`src/lumina_core_shim.c` | 有界 C ABI、回调、串行和超时隔离 |
| `lib/core_backend.dart`、`response_backend.dart`、`response_context.dart`、`client.dart` | Dart FFI、响应路由、完整查询上下文 |
| `hook/build.dart`、`inputs.json`、包 `pubspec.yaml/pubspec.lock` | ARM64 编译、打包和私有输入摘要；独立校验依赖与应用已验证版本对齐，根锁文件本轮未变 |
| `android/app/build.gradle` | 保留供应商库原始字节用于摘要核对 |
| `lib/services/source/lumina/lumina_executor_io.dart` | 后端探测、诊断选择与实际路由记录 |
| `lib/services/source/sdk_playback_coordinator.dart` | 查询失败时保留手动画质意图和真实错误 |
| `lib/presentation/modern/pages/sdk_player_detail_page.dart`、`player/sdk_*` 相关组件 | 紧凑设置面板、错误恢复与阶段计时 |
| `test/lumina_response_*`、`sdk_playback_*`、`sdk_manual_quality_test.dart` | 协议上下文、错误语义、布局与恢复回归 |
| `tool/lumina_core_compare.dart`、`tool/test-lumina-core-contract.ps1`、包 `test/native/*` | 独立验收入口，均非生产运行依赖 |
| `tool/measure-lumina-visible-frame.cjs` 及其测试 | 外部粗粒度画面采样，区分尺寸回调与可见内容 |
| 本报告、SDK README、`docs/release/build-inputs.zh.md`、`docs/development/source-sdk-onboarding.zh.md` | 接入、复现、构建输入和兼容边界说明 |
| 忽略的 `native/libcore_android_arm64.so`、`assets/lumina_private/profile.json` | 私有构建输入，不提交凭证或协议配置 |

备份：`D:/project/Playra-backups/lumina-core-20261019`。`installed-before.apk` 是改动前可运行 x86_64 包，版本号同为 24308，可覆盖恢复而保留数据；源文件和私有输入原件见该目录清单，布局前快照在 `before-layout/`。

本机 ARM64 包采用 `flutter build apk --release --target-platform android-arm64 --build-number=24308`，诊断包额外加 `--dart-define=PLAYRA_DIAGNOSTICS=true`。独立验收使用 `--target tool/lumina_core_compare.dart`，正式包使用 `--target lib/main.dart`。不拆分 ABI，避免 ARM64 分包的旧版本号低于当前 x86_64 安装；源码 pubspec 版本未改。后续升级应继续使用不低于当前安装的版本号，覆盖安装用 `adb install -r`，不卸载、不清数据。

正式产物为 `build/app/outputs/flutter-apk/Playra-arm64-lumina-core.apk`，48,871,546 字节，SHA-256 `d610a1d3f363b88176acb1e3b42e93371aaab263a6ea1251d8c9ae6cb1d26a1a`。正式构建没有启用 `PLAYRA_DIAGNOSTICS`，忽略诊断后端选择文件；同名副本保存在上述备份目录。

新版私有包：`lumina-native-v2.private.json.gz`，SHA-256 `d17a42456f864dfa36fb354c1e7649027afbeebe757972ea8bfab665a689d720`。CI 的私有输入 URL/SHA 仍需指向这份新包，旧包会在写入前被完整性校验拒绝；本次没有上传私有包或修改外部 secrets。

## 兼容限制

适配层与 Android `_fuse` 为 16 KiB LOAD 对齐；供应商 `libcore` 仍为 4 KiB。代码在大页环境不尝试启用该加速器，但这不等于整包已经满足 16 KiB 设备或发布要求，仍需要合规的供应商产物与真实设备验收。参见 [Android 官方 ELF 对齐检查](https://developer.android.com/guide/practices/page-sizes#elf-alignment)。

官方版本化 C 头文件、iOS device/simulator 产物和 ARM64 真机性能验收仍是后续交付边界。
