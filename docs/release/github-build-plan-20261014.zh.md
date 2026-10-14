# Playra GitHub 构建与首页入口修复

基线 `ed0a36df`，远端 main `24e04806`。用户授权：检查仓库与 agents 页面，跑通未签名 iOS 包；安卓继续本地，其他平台使用 GitHub 构建；将实际验证后的流程沉淀为 Skill。追加：恢复首页顶部推荐、热门。

复杂度 L，AIDE-5 研究、设计、实现、验证、审查。修改范围：发布/质量工作流、必要的平台构建设置、打包/验证工具及测试、发布文档，截图测试的干净克隆修复，首页顶部入口及对应组件测试，新增的 Playra 专用 Skill。保留之前未跟踪分析文档与子模块状态，不上传私有 SDK 或签名凭据，不自动发布商店或 GitHub Release。

## 已确认

- GitHub 插件已连接 haigepor；仓库公开，具备维护权限；Actions 已启用。默认分支 main 未包含本地最近的搜索、播放器和 iOS 页面改动。构建必须指向包含这些提交的完整 SHA。
- `/agents?author=haigepor` 属于代理会话入口；当前浏览器返回 404，不能读取其中的会话状态。持续可复现的打包应由 `.github/workflows` 的 GitHub Actions 负责，不从 agents 页面是否可见推断构建状态。
- 远端只有质量和 Android/Web 发布工作流；没有 iOS job，Actions Secrets 列表为空。未签名 iOS 不依赖安卓密钥或私有 Python SDK；Android 内置 SDK 构建仍需相应输入。
- 最新质量 job `115265824908` 在 `content_skeleton_test.dart` 失败：未创建 `.dart_tool/content-skeleton-before-20261012` 就写预览图。必须修复测试自身，不能关闭测试或只在 CI 预建本机专用目录。
- `pubspec.yaml` 固定 Flutter 3.47.6，官方 macOS x64/arm64 发布清单均有对应版本。iOS 工程基线最低版本 13.0，需由真实 CocoaPods/Xcode 解析验证依赖的最低要求。
- Flutter 3.47.6 官方工具源码在 `--no-codesign` 时跳过 IPA 导出。采用 `flutter build ios --release --no-codesign` 得到 device `.app`，按 `Payload/Runner.app` 手工封装明确标记 unsigned 的 IPA，并验证结构、版本、架构和校验和。未签名产物不能直接安装到普通 iPhone。
- 推荐/热门逻辑未删除，但顶部仅展示四分类；两者藏在动漫子筛选且其当前状态会隐藏筛选。恢复为推荐、热门加四分类的顶部浏览入口，动漫子分类保留题材筛选。

## 计划与回退

1. 修复干净克隆截图测试与顶部推荐/热门，执行定向和全量验证。
2. 将云端平台构建与 Android 正式签名分离；从现有默认分支已注册的 release 工作流指定功能分支运行，不必为验收自动合并 main。
3. macOS runner 构建 iOS；Web/Linux/Windows/macOS 使用对应 runner 与实际依赖。每份附件包含 source SHA、版本、工具链和 SHA256。
4. 下载真实 run 附件，校验 iOS 包内容、签名状态和版本。构建成功不冒充真机播放验证。
5. 将确认过的命令、错误恢复、输入边界、验收和 near-miss 触发场景写入新 Skill，校验并打包。

回退只 revert 本轮提交；云端运行不会自动创建 Release，Skill 是新增目录，可移除新增目录回退。默认分支不强推或重置；请求 Skill 沉淀不授权修改全局 AGENTS/config 或记忆。

## 官方依据

- [Flutter iOS 发布流程](https://docs.flutter.dev/deployment/ios)
- [GitHub 手动运行工作流](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow)
- [GitHub agents 会话管理](https://docs.github.com/en/copilot/how-tos/copilot-on-github/use-copilot-agents/manage-and-track-agents)
- [GitHub macOS runner 软件清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)
