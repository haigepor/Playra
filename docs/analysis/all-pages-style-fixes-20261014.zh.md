# 全页面样式修复记录

日期：2026-10-14。对应 `all-pages-style-audit-20261014.zh.md` 的 F01–F13；本轮沿用现有深色背景、淡紫色强调与 Flutter 组件，未迁移 UI 框架。

## 修复结果

| 问题 | 本轮结果 | 实现与边界 |
|---|---|---|
| F01 Web 播放工具栏溢出 | DONE | 以真实播放器容器宽度切换布局。560px 以下保留播放、时间、设置、全屏；次要操作进入“更多播放操作”。设置面板限高并可滚动；单集电影隐藏下一集。保持 media_kit 所有的 video/HLS 与生命周期。 |
| F02 动漫横屏未播放时无法打开详情 | DONE | 封面右下增加 48dp“详情与选集”，打开原有侧栏，不提前创建播放器。 |
| F03 影视首页错误的动漫空状态 | DONE | 影视聚合页直接呈现电影/综艺栏目，各自保留请求、空状态和重试；不渲染动漫推荐空提示。无对应榜单分类时不显示占位榜单。 |
| F04 推荐轮播指示器点击区域 | DONE | 保持原有短线视觉，六项点击区域独立排列，每项 26px 宽、40px 高；320/390px、大字体边缘点击测试通过。 |
| F05 播放按钮无名称 | DONE | 动漫封面按钮增加独立 Semantics 边界与状态名称；Web 播放按钮随播放/暂停更新名称，可通过 Enter/空格操作，销毁时解除监听。 |
| F06 主题选项与新版固定深色矛盾 | DONE | 新版显示实际配色说明和字体选项；隐藏对新版不生效的浅色/动态取色/OLED 控件。旧版选项及已存设置保留。 |
| F07 代理表单风格与提交状态不一致 | DONE | 原生新版使用公共表单卡片、行内提交、忙碌状态、错误反馈；阻止重复提交。Web 深链显示能力说明，不提供无效的代理编辑表单。 |
| F08 标题/小字/触达尺寸分散 | PARTIAL | 新版全局工具栏统一 56dp、移动端密度恢复标准；首页搜索/查看更多 48dp，键盘新增 48dp、删除 32dp，推荐 CTA 字号 12。未对所有旧版与密集媒体控件做全仓库 token 重构。 |
| F09 空态/加载/图片失败规格 | DONE（本轮范围） | 通用新版空状态复用次级页模板，居中且小窗口可滚动，标题 16/600；背景图片失败显示静态失败图标，不伪装加载。已有栏目局部空态保留。 |
| F10 错误页与弹层不一致 | DONE（本轮范围） | 新版设置路由错误采用统一失败模板；通用 Material 底部弹层读取当前主题圆角，新版 20，旧版保留旧圆角。未重写播放器专用弹层。 |
| F11 非敏感输入被标记为不允许建议 | DONE | 规则编辑、图片搜索 URL、来源验证码启用输入建议，保留关闭自动纠错；密码/Token 保持敏感输入策略。小米真机键盘行为仍需真机确认。 |
| F12 iOS 启动错误仍走旧页面 | DONE（代码） | 启动存储错误的新版平台选择改为 Web/Android/iOS 共用支持判断。未进行 iPhone 真机验证。 |
| F13 启动页标签旧名称 | DONE | 统一使用“发现/日历”，保持“推荐/热门”为首页顶部内容切换。 |

额外修复：实际 Web 电影测试发现首帧超时后视频仍可能迟到起播。当前媒体真正播放后清除过期重试遮罩与提示；订阅绑定当前播放代次，旧请求的事件不能清除新请求错误。没有改变解析协议、广告校验或线路切换规则。

## 修改文件、影响与回退

基线：`74a0441a5c8b500a4160c0ddeb843725cb68470a`。本轮文件均可通过对应修复提交 `git revert` 回退；提交前也可从该基线取出列出的文件。不要回退已有子模块或未跟踪的 SDK/分析文件。

| 文件 | 用途/影响 |
|---|---|
| `web/index.html`、`web/player/artplayer_bridge.js`、新增 `web/player/artplayer_controls.css` | Web 播放工具栏、自适应、菜单与键盘语义；同时影响动漫/影视的 Web 控件。 |
| `lib/presentation/modern/miomedia/miomedia_detail_page.dart` | 单集下一集入口和迟到起播提示恢复；解析请求契约保持原样。 |
| `lib/pages/video/playback_scaffold.dart`、`lib/presentation/modern/pages/modern_player_detail_page.dart` | 复用侧栏切换入口、动漫封面播放按钮语义。 |
| `lib/presentation/modern/home/modern_home_view.dart`、`lib/presentation/modern/miomedia/miomedia_rank_view.dart`、`lib/presentation/modern/widgets/modern_feature_carousel.dart` | 首页分类、空态、触达区域与轮播。 |
| `lib/presentation/modern/home/home_theme.dart`、`lib/presentation/modern/modern_theme.dart`、`lib/bean/appbar/sys_app_bar.dart`、`lib/presentation/modern/miomedia/miomedia_browse.dart` | 公共尺寸、工具栏、标题对齐和浏览页触达；旧版主题不重构。 |
| `lib/pages/settings/theme_settings_page.dart`、`lib/pages/settings/proxy/proxy_editor_page.dart`、`lib/pages/settings/keyboard_settings.dart`、`lib/pages/settings/interface_settings.dart` | 外观真实能力、代理表单状态、快捷键触达、启动标签。 |
| `lib/presentation/modern/secondary/secondary_theme.dart`、`lib/bean/widget/empty_state_widget.dart`、`lib/bean/card/network_img_layer.dart`、`lib/pages/route_error_page.dart`、`lib/bean/dialog/adaptive_bottom_sheet.dart` | 共享状态/失败/图片降级与弹层圆角。 |
| `lib/pages/error/storage_error_page.dart` | 新版启动错误页平台选择，包含 iOS。 |
| `lib/pages/plugin_editor/editor_form_widgets.dart`、`lib/pages/search/image_search_page.dart`、`lib/pages/info/source_captcha_flow.dart` | 非敏感字段输入建议属性。 |
| 新增 `test/style_home_regressions_test.dart`、`tool/web_backend/artplayer_bridge.test.cjs` | 原问题复现、分类请求隔离、窄屏/大字体指示器点击、媒体生命周期与控件回归。 |
| `docs/verification/android-modern-home-channels-widget.png` | 本轮全量测试重新生成的首页组件截图。 |

## 验证

- 原问题红灯复现：新增首页/轮播 7 项在修复前失败，修复后通过。
- 全量 Flutter：586 项通过。最后追加的小范围播放器状态/语义与首页触达修补后，相关 58 项回归通过；最终播放器合同 7 项再通过。
- Web 控件 Node 测试：6/6 通过，包括播放语义状态切换、监听解绑与不重载 media_kit 媒体。
- 最终分析：`flutter analyze --no-pub --no-fatal-infos` 退出 0，36 条 info，0 error/0 warning；不宣称全仓库无 lint。
- 正常 `main.dart` Web release 构建通过，产物已同步到 9006 服务目录，未使用测试入口。
- 浏览器实测 320/390px 和宽窗口：电影自动解析/加载；320px 设置菜单与静音可用，全屏进入/退出；迟到起播后视频时间推进且重试遮罩消失；动漫横屏详情侧栏可打开；新版外观显示真实配色；Web 代理深链为能力说明；历史空状态居中。
- Android 正常 release APK 构建、签名、CRC、包名 `com.predidit.kazumi`、版本 `2.3.8/20308`、arm64-v8a/armeabi-v7a/x86_64 核验通过，覆盖安装 `emulator-5554` 成功。
- 原生 1.5 倍字体电影首页：正常电影/综艺栏目，无动漫错误空态；搜索和查看更多触达高度至少 48dp。恢复测试前字体设置。
- 同一新包原生播放电影《唐探1900》高速线路 TC，显示真实画面及“正在播放”，进度从 00:39 继续推进；沿用原生播放器的暂停、画中画、全屏与进度控件。
- 证据目录：`.dart_tool/style-fix-20261014/`，包含浏览器快照、控件矩形、播放状态和原生截图。修改文件均通过严格 UTF-8/无 BOM 检查，差异范围检查无越界文件。

## 剩余风险和后续

- iOS 未在本轮重新打包或真机测试；共享 Dart 页面修改不等于 iPhone 已验证。
- 第三方封面接口仍可能 403/502；播放器实际数据和失败占位已区分，上游可用性不属于样式保证。
- 全仓库小字、密集操作和旧版样式的 token 合并列为可选 NEXT，不混入本轮修复。
- 原生无效代理提交/成功代理连接不在本轮网络实测承诺内；本轮只改呈现、忙碌状态与能力门禁。
