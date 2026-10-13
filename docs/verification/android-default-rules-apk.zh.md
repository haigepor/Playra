# Android 测试包与默认规则交付

日期：2026-10-11。项目：`C:/Users/haige/Desktop/Playra`。

## 本次变更

- 保留引导页：Android 仍显示使用约定、更新来源、访问加速；新旧界面共用逻辑。
- 移除引导中的添加规则步骤，以及完成时要求额外安装规则的确认弹窗。规则管理与规则商店继续保留。
- 将本机确认的 16 条动漫规则作为安装包资源，不依赖网络下载；新设备同意使用约定后自动安装。
- 默认规则初始化先读取完整资源，再复用 PluginsController 的串行持久化事务；按来源 ID / 规则名称去重，重试不重复安装，保留已安装的自定义规则，写入失败回滚内存。
- 增加独立 onboardingCompleted 设置：准备好规则不等于已完成引导。新设备未完成引导时重启仍进入引导；旧用户依据已有规则迁移完成状态；完成后删除规则也不会重新触发引导。
- 只打包规则定义，不复制本机播放历史、账号、SourcePolicy 速度样本或分类覆盖。原始安装规则文件保持不变。

规则名单：7sefun、DM84、xfdmnext、MXdm、dalvdm、moonci、mutefun、aafun、akianime、ezdmw、giriGiriLove、sorani、mgnacg、xfdmneo、baimao、AGE。moonci 与 aafun 虽属同站，仍是独立规则。

## 文件与影响

| 文件 | 影响 |
|---|---|
| `assets/plugins/*.json` | 默认资源从 2 条扩展到 16 条，保持动漫类型及原规则配置；其他读取 bundled 资源的入口也会看到 16 条 |
| `lib/plugins/plugins_controller.dart` | 初始化去重、保留用户规则、持久化失败回滚 |
| `lib/pages/onboarding/onboarding_page.dart` | 减少引导步骤、移除额外安装确认、保存完成状态 |
| `lib/pages/init_page.dart` | 根据独立完成状态路由并迁移旧用户 |
| `lib/services/storage/settings_keys.dart` | 新增 nullable bool 完成状态注册项，null 仅用于迁移 |

未升级依赖、修改 Android applicationId 或签名配置。APK 基于当前工作区构建，包含此前已完成的界面与播放调度修改。

## 构建命令

```powershell
.\tool\build-android.ps1 -Release -AndroidSdk C:/Android/Sdk -JavaHome 'C:/Program Files/Eclipse Adoptium/jdk-21.0.10.7-hotspot'
```

入口为正式 `lib/main.dart`。沿用项目 release 构建和现有 debug 测试签名，不作为正式商店签名发布。

## 验证记录

- PASS：4 个修改的 Dart 文件静态分析无问题，格式检查通过。
- PASS：资源共 16 条，名称唯一且全部为 anime；20 个修改文件严格 UTF-8 解码，无 BOM 或替换字符；原始本机规则文件 SHA-256 未变化。
- PASS：引导源码已无 rules 步骤或 SkipRulesDialog，默认规则初始化和引导完成状态仍存在。
- PASS：`git diff --check`。
- PASS：Android release 构建成功（assembleRelease，1157.9 秒）；版本 2.3.8 / 20308，包名 com.predidit.kazumi，最低 Android API 24。
- PASS：APK ZIP 全部条目 CRC 校验；包内恰好 16 条 anime 规则，逐条与工作区资源一致，AssetManifest.bin 包含全部路径。
- PASS：apksigner 验证通过，APK v2 签名有效；使用现有 Android Debug 测试证书，证书 SHA-256：fa4ec0e036ba5760beaab14bed70e1f6d625462317b8a42d828ac7c3797927fe。
- PASS：原生架构包含 arm64-v8a、armeabi-v7a、x86_64。APK 为 80,710,650 字节（约 77.0 MiB）。
- 交付文件：`build/releases/Playra-2.3.8-test-20261011.apk`；SHA-256：`d2663fe7f5f7351210f41a1f71c175c647285424b586f9dff46099cffc86cae9`。
- 构建期间依赖下载耗时较长；旧 Java 8 源级别和弃用 API 警告未阻止构建，没有为此次打包升级依赖。
- 未执行自动页面测试、真机安装或真实来源播放；由用户安装 APK 后验收。

## 手动验收

1. 新设备首次启动完成使用约定、更新来源、访问加速；没有添加规则页面或额外安装确认弹窗。
2. 同意使用约定后，规则管理显示 16 条动漫规则；可在断网情况下完成默认资源安装。
3. 自动准备规则后、完成引导前重启，仍能继续引导，规则不重复。
4. 完成引导后再启动进入默认页面；原有规则和自定义来源不被覆盖。
5. 检查发现、日历、追番、我的以及详情播放、换源、失败重试等此前修改。

## 回滚

本轮开始前已将涉及文件原样保存到 `.dart_tool/android-seed-before-20261011-143405/`，其中 `baseline.json` 记录原有与新增文件。仅回滚本轮差异，保留此前分类和页面改动。完成状态与新增默认资源不需要迁移播放历史。

## 新版默认修正版

首个交付包基于正式 main.dart，androidUiStyle 的默认值仍为 legacy；浏览器预览入口 main_home_preview.dart 则直接传入 modern。此前只验证了包内资源、签名和构建，没有核对首次启动的界面默认值。

本次修正：

- `lib/services/storage/settings_keys.dart`：androidUiStyle 默认改为 modern；注册设备启动迁移标记 androidModernDefaultApplied。
- `lib/main.dart`：Android 初始化存储后、创建界面控制器前，一次性保存 modern 选择，再保存迁移完成标记。覆盖安装已有 legacy 选择也会在本次首次启动切至新版；以后用户主动切回旧版不会被每次启动覆盖。
- 此迁移不改动收藏、历史、规则或下载。其他原生平台仍按现有 supportsModern 限制使用旧界面。
- 当前源码的 InterfaceSettingsPage 包含页面样式入口，条件为 supportsModern。只读设备检查发现本机模拟器安装时间为 17:17:25，早于首个交付 APK 的 22:55 构建时间；这不能证明用户手机的安装状态，手机入口缺失尚未直接复现。

验证：修改的 2 个 Dart 文件格式与静态分析通过；本轮精确差异已检查，无额外依赖或 Android 配置修改。修正版 assembleRelease 构建成功（159.3 秒），APK v2 签名通过，与首个包使用相同证书。ZIP 全部条目 CRC 通过，16 条规则与工作区一致并注册于 AssetManifest。三种架构的 libapp.so 都包含新增 androidModernDefaultApplied 标记；首个交付包没有该标记，且新旧 APK 字节与 SHA-256 不同。未执行自动页面测试或真机安装，实际启动效果仍由用户验收。

最新交付：`build/releases/Playra-2.3.8-modern-default-20261011.apk`，80,712,074 字节（约 77.0 MiB），版本仍为 2.3.8 / 20308；SHA-256：`666cc9972f35abdd0c67b8a2165ac3d86748519346559591b2a41350395973aa`。安装此修正版后，Android 首次启动自动进入新版，无需先找到页面样式设置入口。

本轮原文件备份：`.dart_tool/android-modern-default-before-20261011/`，scope.json 记录 3 个允许修改路径。仅回滚本轮代码时恢复 main.dart、settings_keys.dart 原文件，并保留此前 16 条规则及引导改动；如需重新执行迁移，设备的迁移标记需单独处理。
