# Playra 构建输入

更新：2026-10-19。当前只重新接入 Lumina，应用运行链使用 Dart + C。MioMedia、AniFive、Chaquopy、Python SDK、设备桥和旧算法 HTTP 宿主已退役。通用发布工具 `cloud_build.py` 仍是开发工具，不会进入应用包。

## Lumina 原生私有输入

受版本控制的清单为 `packages/lumina_engine/inputs.json`，当前接入版本为 2。私有文件在忽略目录 `packages/lumina_engine/native/` 与 `assets/lumina_private/`，包括三个平台 `_fuse` 引擎、官方 ARM64 `libcore`、压缩镜像和通道/协议配置；不导入 Python 模块。设备指纹不得放入 profile，每次安装沿用或生成独立持久身份。

```powershell
node tool/lumina-native-input.cjs verify
node tool/lumina-native-input.cjs export D:/private/lumina-native-input.gz
node tool/lumina-native-input.cjs restore D:/private/lumina-native-input.gz
```

导出文件是私有构建输入，不能提交 Git、上传公开附件或粘贴到日志。恢复只接受清单中的固定文件名，所有文件先通过 SHA-256 校验再写入。构建 hook 再次校验目标原生库和数据资产摘要。镜像解压后也校验摘要；应用只从 Flutter 打包的原生库加载代码。

CI 已改为 Node 恢复，须由维护者配置 `PLAYRA_LUMINA_NATIVE_INPUT_URL`（HTTPS 私有输入下载地址）和 `PLAYRA_LUMINA_NATIVE_INPUT_SHA256`（导出工具输出的压缩包摘要）。代码已接线不代表远端 Secrets 已配置或云构建已通过。缺少输入时明确失败，不回退其他 SDK。

ARM64 当前优先使用同进程 C 响应加速器；x86_64/Windows 和原生故障回退使用 `_fuse`。原生调用超时后隔离到进程重启；业务拒绝不切换解码器。供应商库仍为 4 KiB LOAD 对齐，不能据雷电结果宣称 16 KiB 设备合规。新版私有包、复现命令、性能和回滚证据见 [ARM64 接入验收](../verification/lumina-arm64-core-20261019.zh.md)。

本轮可用目标为 Android arm64、Android x86_64 和 Windows x64。ARM32、iOS、Linux、macOS 和 Web 的基础应用可独立保留，当前不登记 Lumina。iOS 缺少交付方引擎；Linux/macOS 二进制兼容性尚未在对应宿主验收；Web 后续应接 Dart Native BFF 或 WASM，不能恢复 Python 服务。详见 [原生引擎边界](../../packages/lumina_engine/README.md)。

私有 profile 与镜像只对 Android/Windows 打包，使用 Flutter 的 [按平台声明资产](https://docs.flutter.dev/tools/pubspec#assets-field) 机制；Web 发布目录不应出现这些私有文件。

## 构建与验收

```powershell
./tool/build-android.ps1 -Release -TargetPlatform android-x64
./tool/build-android.ps1 -Release -TargetPlatform android-arm64
# 独立原生链路验收包，结束后必须恢复正式 main.dart 包。
flutter build apk --release --target-platform android-x64 --target tool/lumina_android_smoke.dart --dart-define=PLAYRA_DIAGNOSTICS=true
```

Flutter 构建与测试应串行执行，避免共享的插件注册表被不同模式重写。只保留一个原生 worker；取消请求丢弃迟到结果，不表示已经中止 C 调用。诊断仅输出阶段、耗时、后端、固定错误码，不输出密钥、鉴权头、报文或完整播放地址。

正式版默认 `PLAYRA_DIAGNOSTICS=false`。本地测试包沿用现有测试签名，覆盖安装保留数据；不等同正式签名发布。Android ID、Dart package、播放器通道与数据目录保持原值。

正式 Android 签名仍需要 `PLAYRA_ANDROID_KEYSTORE`（Base64）、`PLAYRA_ANDROID_STORE_PASSWORD`、`PLAYRA_ANDROID_KEY_PASSWORD`、`PLAYRA_ANDROID_KEY_ALIAS`。构建任务及版本约束见 [平台构建](build-platforms.zh.md)。不会自动发布或创建 Release。

## 备份与旧数据

本次执行前备份在 `D:/project/Playra-backups/lumina-reset-20261019-113222/`，包括工作区快照、私有 SDK 参考、原安装 APK、差异和摘要清单。应用私有数据保留原位；未卸载、未清除应用数据。旧来源收藏与进度继续可读，显示“已移除来源（记录保留）”，不按片名转换为 Lumina 身份。

旧 Python 接入与性能报告属于历史记录，不能据此判断当前 APK 的后端、速度或平台能力。
