# Lumina 2026-10-19 升级与验收

基线：Playra `02fcd555`；新 SDK `88109b2` 加本轮工作区修复。两个仓库均未提交或发布。私有 SDK 未加入 Git，所有 APK 均为本地测试签名，不等价正式签名发布。

## 已实现

| 位置 | 变更与影响 |
|---|---|
| SDK `envelope.py` | 检查 Cb 表是否足量；不足回退原 EBlock，保留损坏数据异常；增加不含报文材料的线程局部诊断 |
| SDK `_soloader/__init__.py` | 超时后隔离该进程直载后端，拒绝排队/后续调用；迟到回调不能被新请求接收；仅版本动作解析 `payload.version`，不将其误当业务明文 |
| SDK `_fuse/__init__.py` | 雷电 `armv8` 且 64 位指针时映射 ARM64；32 位进程拒绝该别名 |
| SDK `test_runtime_boundaries.py` | 20 项离线边界回归，包括表容量、缺表、未知密钥、回调迟到/并发/超时、诊断隔离、版本结构与 ABI |
| SDK `check_all.py` | 标准库测试 API 标识符按 AST 识别，避免正常测试替身/JSON 序列化名称触发词表；字符串、注释、非绑定名称仍检查 |
| `tool/source_runtime/import_lumina.py`、收据及私有 vendor | v3，33 个固定输入含 `ljc.py` 和 11 份表；暂存校验后成组替换，失败恢复旧目录与收据 |
| `tool/lumina_sdk_input.py` / 测试 | 独立私有输入导出与 HTTPS/SHA256 恢复；限制体积与 ZIP 路径/成员集合，损坏输入不覆盖现有输入 |
| `android/app/build.gradle` | 校验全部输入摘要、打包标定数据、按 ABI 加载只读原生库，保留原生库字节；仅诊断构建打包验收模块 |
| `android_bridge.py`、`lumina_adapter.py`、`SourceRuntimeBridge.kt` | 保留业务/身份/网络边界，增加排队、初始化、HTTP、解密后端与回退、解析器分段诊断 |
| `sdk_player_detail_page.dart` | 仅诊断模式记录渲染器实际首帧；未把直链解析完成当作首帧 |
| Android Java instrumentation、`lumina_verification.py`、`verify_lumina_apk.py` | 固定七操作、同密文 20 轮后端验收；检查实际 APK 字节码、11 份数据、原生库 ABI/摘要/LOAD 对齐 |
| `.github/workflows/release.yaml`、构建输入文档 | Android 独立恢复/验证 Lumina 私有输入；补输入测试和运行时回归；尚未配置远端 Secrets 或触发 CI |

保留七项业务操作、公开返回结构、真实集名、4K 优先与短期直链行为；未引入设备桥、未迁移 Dart 密码协议、未开放 iOS/ARM32。

## 新发现的兼容问题与修复依据

1. 雷电 ARM64 Chaquopy 的 `platform.machine()` 为 `armv8`、指针 8 字节，原平台判定拒绝实际存在的 `_fuse`。新增测试先失败，带指针宽度检查的修复后通过。
2. 官方库初始化成功，版本回复为 `{'action': None, 'code': 200, 'payload': {'version': 51}}`。原 SDK 只识别 `payload.data`，导致直载始终被判不可用。补版本回复结构兼容后，真实业务与同密文对拍通过；业务响应仍要求业务字段。
3. Android 独立 Kotlin 测试入口曾引用被正式包 R8 裁掉的 Kotlin 辅助类。改为 Java instrumentation 后消除测试入口的运行类依赖，未关闭正式包混淆。

## 离线与构建门禁

- SDK `check_all.py`：7/7 门禁通过；两种自检通过、固定向量 11/11；源 SDK 保持占位接入点，命令内真连 E2E 跳过。真连由实际应用七操作覆盖。
- SDK 原目录 20 项边界测试通过；Playra 完整 Python 运行时 **151 项通过**；私有输入 **4 项通过**。
- Flutter 相关 34 项通过：运行桥、Lumina 内容/画质偏好、手动画质、换源集数、播放器行为。修改页面 Dart 分析无 error/warning，保留 8 条既有风格 info。
- 既有 Mio 输入 7 项与云构建工具 6 项测试通过。
- `_fuse` 无设备/官方直载的依赖隔离试验通过；去掉所有引擎后鉴权/请求明确失败，证明当前不是无原生产物的纯算法包。
- 对修改文本执行 UTF-8/语法及 `git diff --check`。SDK 已有 `ljc.py` 打开表时的 ResourceWarning 尚存，不改变算法结果。
- Gradle 将收据、全部平台原生资产及诊断开关纳入增量输入。实际临时改为不兼容收据版本时构建拒绝；恢复原字节后同一暂存任务通过，避免增量缓存跳过校验。
- 官方 ARM64 `libcore.so` LOAD 对齐为 4096；Android 两个 `_fuse` 为 16384。雷电页大小 4096，不声明整个应用已支持 16KiB 设备。

## 雷电实际应用验收

设备：`emulator-5554`，雷电 Android 14，x86_64 内核，ARM64 包经 `libhoudini.so` 翻译。所有安装使用 `install -r -t`，未卸载或清除数据。包名、签名与原数据路径保持兼容。

ARM64 最终诊断 APK 七项操作均成功，实际响应后端全部为 `soloader`：

| 操作 | 单次包含宿主适配的耗时 ms |
|---|---:|
| config | 1529.666 |
| channels | 152.097 |
| banners | 176.333 |
| catalog | 540.137 |
| search | 162.480 |
| detail | 142.149 |
| play | 1024.550 |

ARM64 SDK 冷初始化单列为 470.324ms；首次 config 还包含网络与直载初始化，不把该项当热态响应。

同设备同一份 2905 字节配置响应，先单列首个测量，再各取 20 次热态（p50 中间两项均值，p95 第 19 个排序样本）：

| 后端 | 首个测量 ms | 热态 p50 ms | 热态 p95 ms | 明文一致 |
|---|---:|---:|---:|---|
| ARM64 `fuse-eblock` | 928.435 | 954.429 | 1154.515 | 是 |
| ARM64 `soloader` | 38.448 | 38.161 | 61.789 | 是 |

最终 x86_64 诊断包同样七操作全通过，实际后端 `fuse-eblock`；20 次热态同密文解密 p50/p95 为 428.226/521.117ms，首个测量 451.229ms。此 ABI 没有官方 `libcore.so`，直载不可用是预期结果。两端采集的是各自响应，不作跨 ABI 性能比例比较。

该结果证明这份密文在本设备上直载路径更快，不代表整机/真机/所有响应的提速比例。首次测量前已完成业务调用，因此“首个测量”不是原生冷启动。

两次 ABI 安装后的身份文件摘要一致；11 份标定表在 APK 内实际读取、各 84 行，汇总摘要与输入相同。当前真实响应仍不命中随包表时，`_fuse` 回退已验证。

ARM64 搜索结果、Lumina 详情、实际 1920×1080 视频画面、换第 2 集及持续进度通过；自动 4K 实际显示 3840×2160，手动 1080p 实际显示 1920×1080。对应渲染器首帧样本 1362/4923/1116/1462ms，只作功能证据，不构成首帧分位数。x86_64 同类交互也已验证，最终包复验结果见本机原始报告。

## 产物、复现与回滚

本机审计目录：`D:/project/Playra/.dart_tool/lumina-upgrade-20261019/`，含最终分 ABI 诊断包、最终关闭诊断的 x86_64 包、独立测试 APK、`arm64-report.json` / `x64-report.json`、脱敏分段日志、实际画面截图与输入/原 APK 备份。

输入收据 SHA256：`4bfa3da4351ffc999ee496626048c87f01ab6727cc76bcd3cc8c5a212a65930f`。ARM64 诊断 APK SHA256：`d4ee622c6cd99c99d7151f1040e902550a218ec0c7256e2ed64c559faa4a4ce0`；x86_64 诊断 APK SHA256：`9439ba52950e9e541a40d9fdc905eda0fc52cdae2cf7667aa659f4d5e925e2f0`。

最终日常测试包 `Playra-lumina-x64-release.apk` SHA256：`2ce98588d6b1f45cb0b86d5adaec69a5a88441de944b8562ea56befd5e3c9bd7`，诊断关闭且验收模块不在 APK 中，已覆盖安装到雷电；应用新进程没有本轮 `PLAYRA_LUMINA` / `PlayraRuntime` 诊断输出。未清数据，原观看历史保留；已验证自动 4K 的 3840×2160 实际画面与续播，最终偏好保留“自动（4K 优先）”。

```powershell
# Python 3.11 与 APK 中 Python 版本一致；可先激活本地开发环境。
python -B -X utf8 tool/source_runtime/import_lumina.py --verify
python -B -X utf8 -m unittest discover -s tool/source_runtime -p 'test_*.py'
python -B -X utf8 -m unittest discover -s tool -p 'test_lumina_sdk_input.py'
python -B -X utf8 tool/verify_lumina_apk.py <APK绝对路径> --abi arm64-v8a --diagnostics
# 安装同签名诊断包与独立测试 APK 后：
adb -s emulator-5554 shell am instrument -w com.predidit.kazumi.test/com.example.kazumi.LuminaInstrumentation
```

私有输入本机导出为 `.dart_tool/private-sdk-input/lumina-sdk.zip`。CI 使用新引入的 `LUMINA_SDK_BUNDLE_URL` 和 `LUMINA_SDK_BUNDLE_SHA256`；需要维护者在受控存储/仓库配置后才能验证远端干净构建，本轮未代为上传私有输入或修改远端 Secrets。

回滚：审计目录 `backup/vendor-lumina/`、`backup/lumina-manifest.json`、`backup/sdk/`、`backup/app-release.apk` 和 `backup-inventory.json` 保留原字节；旧项目输入本就与旧收据不一致，直接恢复会同时恢复原完整性问题。升级工具对新的有效输入支持目录/收据成组回滚；如恢复旧 APK，使用同签名覆盖安装并保留应用数据。源码恢复需按此表逐项比对备份，不能对两个仓库执行整体 reset。

跨端结论及未来本地方案见 [Lumina 原生依赖与跨端架构](../analysis/lumina-cross-platform-architecture-20261019.zh.md)。待外部条件：ARM 真机、16KiB 环境、远端 CI 配置；iOS 本地引擎/协议迁移是后续独立工作。
