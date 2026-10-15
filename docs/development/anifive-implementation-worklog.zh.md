# 四源动漫接入实施记录

基线：37501c88efff；任务复杂度 XL，按运行时、迁移、媒体、双端验证四个切片交付。

用户已批准执行四源方案。保留既有未跟踪文件 `docs/project-analysis-20261013.md` 和前轮分析文档。

允许修改：`tool/source_runtime/`、`tool/web_backend/`、`assets/plugins/`、新增迁移资产、`lib/plugins/`、来源/视频解析服务与播放下载消费点、相关历史恢复入口、`android/app/build.gradle`、必要的平台桥、专项测试及接入/验收文档。`.gitignore` 仅增加私有 SDK 输入。不得修改全局控制文件、用户 SDK 原目录、Mio 算法或无关界面。

目标：默认四源；旧规则幂等迁移及可回滚备份；自定义规则/历史/收藏保留；共用受限运行契约；Web 和雷电模拟器实际播放验证。

回滚：代码基线以上述提交为准；运行数据使用迁移前原始快照，禁止通过重置整个用户目录回滚。

验证：Python 契约/网络边界、Dart 迁移/头策略/历史回归、Node HLS 网关、Flutter 分析和两端构建、实际播放器起播/换集/恢复及取消验证。

## 2026-10-15 实施状态与证据边界

本节整理本会话已完成的检查，不表示后续文档整理时重新运行了全部应用验收。后续新增 SDK 使用[统一接入规范](source-sdk-onboarding.zh.md)及[验收模板](templates/source-sdk-checklist.zh.md)。

| 项目 | 结果 | 已有证据 / 尚缺证据 |
|---|---|---|
| 四源默认资产和SDK运行 | DONE | `DM84/MXdm/akianime/moonci` 四个资产；HTTP/Android共用 `dispatch.py`；私有导入清单及随包检查 |
| 旧规则迁移/媒体头/历史身份/封面 | DONE（实现和专项测试） | 原16条快照、同名自定义项保护、备份/幂等标记、真实URL恢复、replace头策略；不代表所有存量设备均实测 |
| Python专项 | PASS | 会话运行 `test_anifive_covers/test_anifive/test_server/test_android_bridge/test_sdk_http`，46项通过 |
| Flutter专项 | PASS | 会话先运行历史/播放器/来源等52项通过；后运行封面/迁移/头/历史/API配置/来源49项通过，两个批次有重叠，不相加当独立总数 |
| Web网关 | PASS | Node测试25项通过；HLS重写、Range、跨域头过滤和取消回归包含在内 |
| 独立Dart运行链路 | PASS | `tool/source_runtime_integration.dart` 的21项HTTP/同源桥/Python/真实RuleEngine检查通过 |
| Web与Android构建 | PASS（当时产物） | `build/web` 与 `build/app/outputs/flutter-apk/app-debug.apk`；后续源码修改需重建，不把旧包当新代码 |
| Web真实播放 | PASS（样例） | 正式页面搜索进入MXdm，1280×720，30秒时727帧；下一集持续播放并写入第2集0:49历史；moonci MP4样例1920宽、14秒以上、readyState=4 |
| 首页和搜索封面 | PARTIAL | 首页四张Bangumi封面已恢复并截图；四源样例取得封面字段；部分第三方CDN失效/占位广告仍存在，不能标全图通过 |
| Android实际持续播放 | BLOCKED | 雷电已连接、升级前数据备份、APK安装和旧规则迁移已观察；进入播放链路时模拟器连接不稳定，未取得稳定首帧/持续播放证据 |
| 发布CI | BLOCKED | 工作流仅恢复Mio输入，AniFive私有输入恢复未配置；正式签名/发布状态不由本地debug构建证明 |

本机证据：`.dart_tool/anifive-verification/web-home-covers.png`、`web-search-covers.png`；升级前应用数据备份为同目录 `android-before.tar`。这些是忽略的本机文件，不可作为干净克隆中已存在的公共附件。

当前总体为 **PARTIAL**：接入代码和Web样例具备证据，Android实播与干净CI发布未完成。A/C样例的解析及媒体内容检查不替代它们所有线路的播放器实播。

后续：补Android实际包的首帧/持续播放/换集记录，完成AniFive CI输入恢复，核对上游版本收据；完整要求与已知协议差异见主规范第12节。

### 后续验收更新：播放源统一与布局调整

上表是早期接入时的状态快照。后续雷电已取得实际画面、持续播放、手动第2集和重启恢复证据，Android实播的旧BLOCKED状态已解除；发布CI仍为独立未完成事项。新版两端构建、来源分组、紧凑布局与新页面Token继承记录见[播放源实施验收记录](anime-playback-source-alignment-verification-20261015.zh.md)，不将旧包或旧截图充当最新版本证明。
