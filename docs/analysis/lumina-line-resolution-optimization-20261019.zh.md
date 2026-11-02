# Lumina 线路解析：快路径核验与优化

日期：2026-10-19。延续 Dart + C 方案；不恢复 Python、设备桥或其他接口 SDK。本文修订前次报告的性能归因，并记录本轮变更、测试与可验证的性能边界。

## 1. 先确认调用事实

当前 Dart 的 `_calibrate`、参考 SDK 的 `_fuse.calibrate_direct`、`EBlock.calibrate` 快路径以及 `ljc.CbQuery`，底层均为 **一次 `lumafuse_calib_direct(K, nblk, ...)`**。没有在接入侧循环执行 256 次单块 FFI。

项目与 SDK 目录中的 Windows DLL SHA-256 相同：`294c98277efba7aba154b5fd2a583f59c3e964edaebbacf6875bf30c42fbcff3`。读取现有签名和实现后，以同一进程、同 DLL、同 K、同 256 块交替调用 EBlock 和直接 C，结果如下。两者返回的 CONST/Cb 逐字节一致。

| 轮次 | 新 EBlock 会话首次标定 | 直接 C 标定 | 同 EBlock 再标定 | 首次 / 再次 C 调用数 |
|---|---:|---:|---:|---:|
| 0，含初轮影响 | 507.729 ms | 427.507 ms | 0.0017 ms | 1 / 0 |
| 1 | 540.711 ms | 433.433 ms | 0.0019 ms | 1 / 0 |
| 2 | 433.532 ms | 420.822 ms | 0.0014 ms | 1 / 0 |
| 3 | 430.586 ms | 426.424 ms | 0.0074 ms | 1 / 0 |
| 4 | 415.738 ms | 416.277 ms | 0.0013 ms | 1 / 0 |
| 5 | 412.294 ms | 439.881 ms | 0.0016 ms | 1 / 0 |

因此，“旧接法 1,034 ms 意味着逐块往返，换成 EBlock 就自动变成 377 ms”不能作为当前代码的结论。此前 1,034 ms 是当时环境下的分段样本；本轮没有证明其差异的具体系统负载来源，也不把本轮约 430 ms 的 fresh 标定归功于改了 C 入口。

**确实缺失且已经补齐的是会话内同 K 缓存。** 如果真实的新响应换了 K，旧 K 的缓存不能帮助它。`CbQuery` 也仍然调用同一标定原语，不等于拿到了另一份免标定 C 算法。88 ms 或任何一次实测下界不应被表述为协议的数学性能下限。

Python 仅用于本机离线对照供应商参考，不进入应用或构建依赖。复现脚本和脱敏数值位于本地审计目录的 `compare_calibrate_entry.py` / `calibrate-entry-comparison.json`。

## 2. 已完成的变更

### 原生同 K 缓存

`packages/lumina_engine/lib/lumina_engine.dart` 保留整链一次标定，按密钥复用 C(K)、CONST 和 Cb。缓存最多 8 个密钥、2 MiB 链表；所需块数不超过已标定容量时复用前缀，容量不足时重新整链标定。Arena 内存复制到 Dart 管理的字节数组后才缓存，不保留已释放的指针。

新增 `calibration / calibration_hit / decrypt_chain` 分段诊断，均不输出密钥。缓存可显式清空，Client 关闭时释放其缓存引用。

### 空闲预加载与取消边界

`LuminaWorkScheduler` 允许前台网络请求重叠；后台预热等待前台请求结束并连续空闲 3 秒，多个后台请求依次执行。新的前台请求立即取消当前后台等待，并停止尚未进入 C 的后台解密。宿主向 worker 传递取消标记，Client 在进入解密等同步阶段前检查该标记，不只是丢弃最终结果。

这不是任意时刻都能抢占 C 的独立执行上下文。**已经开始的同步 C 调用仍须返回；不能保证排队为 0。** 当前 C 引擎含进程全局状态，另建 isolate 或 Client 并发调用同一个库，不会自动获得独立原生上下文。真正的计算隔离需要正式的 context/handle ABI，或经验证的独立进程方案，不能以“零风险”名义直接并发。

后台频道因前台让路而被打断后，会再次经过空闲门禁重试该频道；页面销毁或用户取消则停止。不会把一次内部调度取消当作频道永久失败。此回归先复现“只执行一次、频道未缓存”，修复后确认第二次成功。

### 同集多画质结果复用

`LuminaPlaybackProvider` 在原有 27 秒窗口内按作品、线路、真实集名保存整份解析结果，切画质只选择 SDK 实际返回的对应地址。不根据同一 CDN 域名猜测或拼接变体路径。

缓存读取不更新原始解析时刻；传给通用 `PreparedPlayback` 的媒体带有绝对有效期，防止下游再次缓存时延长寿命。若上游已给出更早的有效期，则保留更早者。媒体拒绝、打开失败或 `EXPIRED` 重试时，通过通用 `invalidatePlayback` 钩子先淘汰原同集材料，再刷新凭证；不会反复重用坏地址。预取消不能消费或返回材料。

## 3. Windows 同密文 20 次对照

固定 K 和 4,112 字节密文，对应 4,096 字节明文。相同引擎和同一进程内，分别测试每次清除标定缓存与缓存命中。初轮预热不计入分位数，所有明文匹配。

| 指标 | p50 | p95 |
|---|---:|---:|
| 清缓存后的解密总时长 | 431.383 ms | 547.346 ms |
| 其中标定，含 C(K) 推导 | 431.227 ms | 547.174 ms |
| 同 K 缓存命中的解密总时长 | **0.108 ms** | **0.161 ms** |

20 次缓存命中未再次执行标定。另验证已缓存长表解密短输入、不同密钥与密钥淘汰后的明文正确性。该结果不包含 HTTP、RSA、解析器和播放器，不能当作 Android 的线路就绪或首帧时长。

可复现入口：从 `packages/lumina_engine` 执行 `dart run bin/benchmark.dart <image.bin> <report.json>`。私有输入仍在原忽略目录，未提交密钥、鉴权头、报文或播放地址。

## 4. 验证

- 新增的同集切画质测试先复现两次 `play`，随后确认只请求一次；过期窗口、取消和媒体拒绝刷新分别测试。
- 定向 32 项通过；完整 Flutter 回归 **710 项通过**。其后补齐预加载中断重试，相关 12 项再次通过，重叠用例不相加为独立总数。
- `dart analyze .` 退出 0，112 条 info，无 error/warning；未将旧项目 lint 提示当成零提示。
- 供应商参考生成的 11 组块向量、3 组鉴权向量，以及 8 项原生/协议检查通过。
- Windows 七类真实操作及媒体分段读取通过；新增预 HTTP 取消和总超时检查通过。这些单轮业务耗时没有被当作性能分位数。

雷电功能和阶段日志在本轮补录中单列；本节的 Windows 分位数不用于预设 Android 提速比例。即使缓存命中，打开另一画质的媒体仍可能需要重新连接、缓冲和解码，不能把本地选 URL 的耗时称为首帧约 100 ms。

### 雷电 x86_64 补录

在 release 诊断包执行与旧版相同的“主频道目录返回后立即点击作品”步骤：

| 指标 | 优化前复现 | 优化后复现 |
|---|---:|---:|
| 详情进入 worker 的排队 | 1,733.860 ms | **0.096 ms** |
| 播放进入 worker 的排队 | 3,061.169 ms | **0.125 ms** |
| 播放响应解密 | 791.377 ms | 774.955 ms |
| 解析器 HTTP 阶段 | 1,678.493 ms，跨越其他目录解密 | 643.640 ms |

新样本从点击作品到观察到解析完成日志约 **2,054 ms**，含详情请求和日志轮询误差；不将其等同于播放接口自身耗时。这不是多轮 Android p50/p95，对照响应也不是固定密文。可确认的是该次前台请求没有排在预热解密后面，不能推导所有时刻排队都为 0。

随后在材料有效期内切换 1080p、自动，两次操作均未产生新的 `play / decrypt / resolver` 诊断记录，截图分别显示正确的 1080p / 2160p 准备结果。再实际打开视频并切换画质，解码尺寸为 3840×2160 / 1920×1080，播放器打开到首帧分别约 1,540 / 1,320 ms。该首帧阶段另计，证明缓存命中不意味着媒体切换可在 100 ms 内完成。

二次同密文 20 次复核仍得到未缓存解密 p50 430.452 ms、缓存命中 p50 0.143 ms，并通过“超过 8 个密钥后必须重算”的检查。原始脱敏数值、截图及阶段日志位于本地审计目录 `perf-after-preload.*`、`perf-quality-after.*`、`perf-first-frame.log`、`perf-playing-quality.log` 和 `native-cache-benchmark-checked.json`。

## 5. 文件、影响和回滚

| 文件 | 目的 |
|---|---|
| `packages/lumina_engine/lib/lumina_engine.dart` | 有界同 K 缓存、容量检查和分段诊断 |
| `packages/lumina_engine/lib/client.dart` | 阶段前检查取消；传递原生诊断；关闭时清缓存 |
| `packages/lumina_engine/bin/benchmark.dart`、`bin/live.dart` | 同密文可重复测试及取消验收 |
| `lib/services/source/lumina/lumina_work_scheduler.dart` | 前台优先、后台空闲门禁 |
| `lumina_executor_io.dart`、`lumina_home_controller.dart` | 调度接线、worker 取消标记、预热后台标记 |
| `lumina_playback_provider.dart` | 同集多画质短时复用、绝对期限和失效处理 |
| `sdk_playback_provider.dart`、`sdk_playback_coordinator.dart` | 通用失效钩子及媒体失败后刷新 |
| `test/lumina_quality_preference_test.dart`、`test/lumina_work_scheduler_test.dart`、`test/lumina_preload_retry_test.dart` | 真实调用编排、TTL、调度和中断后重试回归 |
| 本报告、原性能报告、引擎 README | 修订证据与运行边界 |

本轮核心文件的修改前备份位于 `D:/project/Playra-backups/lumina-perf-20261019/`。上一轮完整迁移备份仍位于 `D:/project/Playra-backups/lumina-reset-20261019-113222/`。回滚仅恢复本轮相关文件和新建文件，不执行整体 reset、不卸载应用或清除数据。

## 6. 后续能力边界

最终普通入口 release APK（`PLAYRA_DIAGNOSTICS=false`）已分别构建，私有资产及原生库摘要与清单一致，未重新引入 Python/Chaquopy：

| ABI | 大小 | SHA-256 |
|---|---:|---|
| ARM64 | 46,280,852 B | `a9fa5272b16e98c6a6794f346b704ca831f4cc40f477ee302ec3a7e62675a835` |
| x86_64 | 47,470,117 B | `389ee1a58e0e5b2f322d7dd68c73b99462cde43e03867afa1578513a768bcb01` |

最终在雷电覆盖安装 x86_64 普通入口包，保留原应用数据。ARM64 本轮完成编译和静态校验；由于已有 x86_64 分包版本码更高，继续保留原数据，不卸载来强制切换 ABI。因此本轮 Android 优化实测仅代表雷电 x86_64，不能冒称 ARM64 或真机测量。APK 和关键日志同时保存至本轮持久备份目录。

- DONE：核验当前已走一次 C 标定快路径，纠正按耗时猜测调用次数的结论。
- DONE：同 K 有界缓存、空闲预加载、取消传递、短时多画质复用与失效刷新。
- DONE：Windows 同密文分段和参考 SDK 对照，回归与真实接口检查。
- DONE：最终两种 ABI 编译与静态摘要核对，雷电 x86_64 普通入口覆盖安装；保留应用数据。
- NEXT：按设备分别统计点击到线路就绪和实际首帧的冷热分位数，不预设 0.7–1.0 秒目标已经达成。
- NEXT：按正式契约补进程内 ARM64 官方库后端，继续保持无 Python、无设备桥。
- BLOCKED：跨端独立原生上下文及 iOS 引擎交付，缺少正式 context ABI 和对应产物。
