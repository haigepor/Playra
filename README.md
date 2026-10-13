# Playra

Playra 是基于 Flutter 的影音应用，在 Kazumi 开源项目基础上接入内容 SDK，并完善发现、榜单、选集和播放界面。当前重点验证 Web 与 Android。

## 本地开发

Flutter 版本见 `pubspec.yaml`。Windows 项目工具链位于 `.tooling/flutter`；也可使用相同版本的系统 Flutter。

```powershell
flutter pub get
flutter analyze --no-fatal-infos
flutter test
python tool/miomedia_sdk_input.py sync --sdk-directory C:/path/to/sdk/python/miomedia
```

Android 内置 Python SDK，正常使用无需连接开发电脑。私有 SDK 不提交公开仓库，构建前必须准备完整模块与查表资源，见 [构建输入](docs/release/build-inputs.zh.md)。Web 的内容服务配置见 [接入说明](docs/miomedia-sdk-integration.zh.md)。

## 版本与发布

- 应用显示名统一为 Playra；兼容安装 ID 与数据路径保留，避免升级丢失记录。
- 正式构建隐藏诊断与实验入口，关于页提供帮助、隐私说明和许可信息。
- 自有版本 tag 使用 `playra/v*`；官方源码通过 `upstream` 和 `kazumi-upstream` 保留，见 [引用策略](docs/release/tag-policy.zh.md)。
- [Playra 发布版本](https://github.com/haigepor/Playra/releases)是本项目更新源。真机播放尚未完成复验时，不把构建附件作为正式发布验收结果。

## 验证

```powershell
flutter test
python -m unittest discover -s tool -p test_miomedia_sdk_input.py
cd tool/source_runtime
python -m unittest discover -p 'test_*.py'
```

SDK 自检和真机对照要求见 [构建输入](docs/release/build-inputs.zh.md) 与 `docs/verification/`。SDK 全程使用 Python 标准库，不修改已经验证的密码算法。

## 许可与致谢

沿用 [GNU GPL v3.0](LICENSE)。感谢 [Kazumi 原项目及贡献者](https://github.com/Predidit/Kazumi)，保留原作者及第三方组件版权。原项目历史说明保存于 [Kazumi README](docs/upstream/Kazumi-README.md)，其中安装和发布链接属于原项目。
