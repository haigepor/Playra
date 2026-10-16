# Playra 构建输入

更新：2026-10-15。新增来源的交付要求见[统一 SDK 接入规范](../development/source-sdk-onboarding.zh.md)。Android 包通过 Chaquopy 内置 Python 内容 SDK，不依赖电脑上的 Python 服务。Web 需要算法服务及同源网关。

当前构建要求 **MioMedia、AniFive、Lumina 三套私有输入**；常规运行适配器为`miomedia`、`anifive-a/b/c/d`与`lumina`，ARM32不登记Lumina。三个vendor目录均被忽略，干净克隆必须分别恢复；Mio的CI导出不能替代其他两套输入。

## Lumina 私有输入

```powershell
# source必须指向lumina包；实际分配host由维护者显式填写，不使用出厂占位符。
python -B -X utf8 tool/source_runtime/import_lumina.py C:/path/to/sdk/python/lumina --host <assigned-host>
python -B -X utf8 tool/source_runtime/import_lumina.py --verify
```

导入器只允许`config.py/profile.py`环境绑定差异，其他算法与上游摘要逐字节一致；可提交的`vendor/lumina-manifest.json`仅包含摘要、大小和平台，不包含host、设备指纹或密钥。运行时在各宿主私有目录生成并复用32位十六进制指纹，禁止把开发机identity打包给所有设备。源码SDK和vendor算法不得提交到公共Git。

Android通过`stageLuminaJni`将arm64/x86_64原形引擎分别安装为`lib/<abi>/liblumafuse.so`；`stageEmbeddedPython`仅打包Python模块与`fuse_image.bin.gz`，不打包桌面DLL/so/dylib。Chaquopy仅提取`vendor.lumina._fuse`以支持真实文件路径，库从只读`nativeLibraryDir`加载，解压镜像进入私有缓存。ARM32保留旧来源，不引入Unicorn或伪造后端。

iOS当前不登记或展示Lumina，保留旧动漫来源；本轮暂停本地/远端Lumina研究，已有影视远端配置不代表Lumina能力。历史方案及验收边界见[三端接入与验收](../verification/lumina-sdk-20261016.zh.md)。现有公开CI尚未恢复Lumina输入；未恢复前不能宣称干净云构建就绪。

## AniFive 四源输入

```powershell
python -B -X utf8 tool/source_runtime/import_anifive.py "C:/path/to/sdk/python/anifive"
```

参数必须指向 SDK 的 Python 包目录，不是仓库根目录。导入到 `tool/source_runtime/vendor/anifive/`，生成可提交的 `vendor/anifive-manifest.json`，记录原始及导入后文件 SHA256。原 SDK 目录不修改，项目副本通过导入器应用请求级传输注入、截断处理、证书校验及导入兼容补丁。

必需模块包括 `__init__.py/client.py/transport.py/profile.py/source_a.py/source_b.py/source_c.py/source_d.py/selector.py/codec.py/config.py/clarity.py`。Android 的 `stageEmbeddedPython` 校验这些文件并打包 `vendor/anifive/*.py`、`anifive_adapter.py`、`anifive_transport.py`、`dispatch.py` 等运行依赖。缺输入会明确使 Android 构建失败。

当前导入收据的上游标识为 `dc13fdb`，导入器尚未自动验证输入仓库提交；维护者必须核对实际 SDK 版本及收据摘要。新版 SDK 不应在未核对补丁适用性的情况下直接覆盖现有输入。

**CI 尚未完成 AniFive 输入恢复。** 当前 `.github/workflows/release.yaml` 只调用 Mio `import-env`，没有 AniFive 导入步骤。新增 CI 输入须单独设计存储/恢复/完整性校验，完成干净环境构建后才可标记发布就绪；不要创建尚不存在的 Secret 名称作为既有要求，也不要把 vendor 包上传成公开构建附件。

## MioMedia 输入与既有 CI

SDK 原始模块含内部配置和自检向量，整个 `tool/source_runtime/vendor/miomedia/` 作为私有构建输入忽略，密码算法不作修改。干净克隆后先准备 SDK：

```powershell
python tool/miomedia_sdk_input.py sync --sdk-directory C:/path/to/sdk/python/miomedia
python tool/miomedia_sdk_input.py check
```

SDK 自检分别在模块目录运行 `python selftest.py`，在 vendor 父目录运行 `python -m miomedia.selftest`。播放模块应为 12/12。

核心输入为原有 12 个文件，包括 `bf_tables.bin`。新版 `suite.py` 引用 `_native` 时，还必须包含原 SDK 的 `_native/__init__.py`，此时同步与导出共 13 个文件。同步工具会拒绝缺少这个桥的输入。`fast.dll` 等原生加速库可选；Web 服务和 Android 均可使用原 SDK 的纯 Python 回退，Android 打包不包含 Windows DLL。输入检查通过仅证明文件及语法有效，仍需运行上述两种自检。

本机 D 盘开发环境、缓存位置与激活方式见 [Web/Android 开发环境](../development/web-android-environment.zh.md)。

CI 使用 `python tool/miomedia_sdk_input.py export` 生成两份忽略的输入文件，分别存入仓库 Actions Secrets `MIOMEDIA_SDK_BUNDLE_1` 与 `MIOMEDIA_SDK_BUNDLE_2`，不提交文件、不粘贴内容到日志。使用两份是因为当前编码后约 61 KB，超过单份 Secret 48 KB 限制。[GitHub Secrets 文档](https://docs.github.com/en/actions/how-tos/write-workflows/choose-what-workflows-do/use-secrets)

正式 Android/Web 构建仍接受 `playra/v*`，校验 tag 版本与 pubspec 一致。另有手动的独立 iOS/Web/macOS/Linux/Windows 构建入口，详见 [平台构建](build-platforms.zh.md)。附件不自动创建 GitHub Release。Android 签名所需 Secrets：`PLAYRA_ANDROID_KEYSTORE`（Base64）、`PLAYRA_ANDROID_STORE_PASSWORD`、`PLAYRA_ANDROID_KEY_PASSWORD`、`PLAYRA_ANDROID_KEY_ALIAS`。缺少私有 SDK 或正式签名配置时 Android CI 明确失败；独立 unsigned iOS job 不依赖这些输入。不得上传私有 SDK 输入附件。

本地测试包沿用当前测试签名，可覆盖现有测试安装并保留数据；它不等同正式签名发布。正式版默认 `PLAYRA_DIAGNOSTICS=false`；如需诊断测试包，显式传入 `--dart-define=PLAYRA_DIAGNOSTICS=true`。

底层 Android ID、Dart package、MethodChannel 与数据路径暂保留历史值以保证升级兼容。系统显示名、网页标题和应用文案统一为 Playra。应用关于页面隐藏外部源码入口；源码中的许可与原作者署名保留。
