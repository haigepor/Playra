# 放送日历与弹窗优化 · 2026-11-09

本文归档日历与弹窗这一轮的结果。后续首页顶部及空状态改动、提交前检查与当前原生验收边界见 [本次改动汇总](../verification/ui-change-delivery-20261109.zh.md)。本文记录的 APK 不包含后续首页修改。

## 本次结果与证据边界

本轮已修改 Playra 的放送日历、排序弹窗、追番管理、追番状态选择与日历筛选开关，继续使用项目现有 Forui 0.27.7 主题。没有更换组件库、复制追剧喵配色或修改私有输入校验。

追剧喵原版 APK 已真实安装并启动，但停在启动页。随后雷电失去 shell 响应；一次实例重启和一次关闭后重新启动均未恢复 Android 启动。本轮没有完成追剧喵首页、分类、播放页和弹窗的实际逐页遍历，也没有完成新版 Playra 在模拟器中的安装复验。下列参考观察来自用户指定目录已有截图及 UI XML，不冒充本次实时结果。

## 参考软件与布局观察

- 原版：追剧喵 4.0.6，versionCode 106，包名 `com.jjpengcheng.callshow.zjmc`。
- 文件：`C:/Users/haige/Desktop/instruct/tv-reverse/workspace/com.jjpengcheng.callshow.zjmc/raw/122_a759733f.apk`。
- SHA256：`a759733f949f70ca77f06cdfba96316c71d9ce0dfb7004bab81c7a59ecd5427c`，与样本清单匹配。
- 原生 ABI 仅包含 arm64-v8a、armeabi-v7a；当前雷电是 x86_64，运行依赖 ARM 转译。

| 页面 | 归档中的可见结构 | 用于 Playra 的取舍 |
|---|---|---|
| 首页 | 搜索入口、首页/电影/电视剧/动漫等顶部分类、分区标题、海报网格、底部导航 | 保持搜索、内容分类、页面导航各自的层级；内容区域减少无关外框 |
| 分类 | UI XML 显示八个顶部标签，内容依分类变化 | 星期导航与筛选是不同层级；不用一条过长下划线连接所有操作 |
| 播放页 | 顶部矩形视频区，视频/讨论标签；片名元信息；换源/下载/收藏/分享一行；选集独立分区；简介在后 | 保留矩形播放区与独立操作行；本轮不再次改写已验证的全屏/PiP 平台逻辑 |
| 公告弹窗 | 装饰性公告卡片，单个确认动作；广告覆盖内容的情况也可见 | 借鉴明确的标题与动作层级；Playra 继续使用统一 Forui 中性表面，不引入广告层或公告插画样式 |

资料位置：该目录 `analysis/ui_dump2.xml`、`ui_gk.xml`、`ui_dump3.xml`、`ui_dump.xml`、`ui7.xml`，以及 `ui7.png`、`detail1.png`、`ui10.png`、`ui11.png`。未发现可确认的追剧喵放送日历页面，因此日历是根据 Playra 自身功能重组。

## 已落实的页面改动

### 放送日历

1. 保留标题与季度入口，小屏大字体继续上下排列；星期选择、筛选、当日内容按顺序分层。
2. 星期选中态使用 Forui `FButton` 的 secondary/selected 状态，去掉额外自绘滑动下划线；触控目标不低于 48dp。字体放大时星期条可横向滚动并将当前星期带入视口。
3. 星期副文字使用 caption 字号。数据未取得时显示占位符，列表标题显示加载状态，不用一排“0部”表示未知数量。
4. “全部 / 仅追番 / 筛选 / 今天”使用现有 Forui 按钮，按可用宽度换行；去掉原先难以解释的红点。额外筛选显示数量及“日漫 / 隐藏看过”等文字摘要。
5. 冷启动加载失败显示一个完整错误区和“重新加载”；不重复出现错误提示，也不会建议通过清除筛选来解决网络错误。重试保留筛选。
6. 已获取数据但筛选为空时提供筛选解释和清除入口；保留数据刷新失败时的旧内容与重试提示。
7. 手机列表与平板双列布局继续使用共享断点、间距、文字缩放规则。
8. 星期条与内容切换共用 `PlayraMotion` 时长、曲线与减少动画设置，删除重复滚动请求；减少动画时直接跳到目标页面。

### 弹窗

1. 排序选项、追番管理、追番状态与日历开关使用 `PlayraListGroup` → Forui `FTileGroup`；每个选项仍是原生 `FTile`，由分组负责分隔与外轮廓，取消每行独立卡片边框。
2. 排序和追番状态使用真实 selected 状态并保留勾选标记；原有选择、关闭、收藏修改与删除确认流程不变。
3. 通用弹层标题与正文之间补齐共享间距；继续保留顶部圆角、底部直角、关闭按钮、安全区、键盘避让和矮横屏高度规则。

## 验证与环境问题

最终 36 项聚焦检查通过，涉及日历交互、加载/失败/筛选空态、重试保留筛选、减少动画切换、追番操作、通用组件与 Forui 主题契约。4 个改动源码文件与日历测试的静态分析通过，无问题。最初新增的减少动画测试因未等待 Forui 按压反馈定时器而在清理阶段失败；保留即时到达断言，并在断言后等待反馈结束，修正后通过。

验证范围和构建收据保存在 `docs/verification/calendar-sheets-20261109/`。Flutter 渲染探针使用项目 MiSans 字体与 Lucide 字体，覆盖 320dp/2 倍文字、390dp、800dp，以及错误状态和排序弹窗；使用明确示例数据，不能作为真实网络数据或原生端验收证据。

雷电网络探针：Android curl 对 `https://next.bgm.tv/p1/calendar` 在域名解析阶段超时，IP ping 成功；此前宿主同接口返回 200。Android DNS 日志同时存在失败服务器和长时间 TLS 查询，尚不足以确定全部根因。

重启后 `VBox.log` 显示：`VT-x is not available`、`WHvCapabilityCodeHypervisorPresent is TRUE`，随后 `Giving up catch-up attempt` 的累计时钟滞后持续增加，ADB 无设备。证据支持当前虚拟机启动异常；没有修改 Windows Hyper-V、启动项、BIOS、全局 Gradle 或重启宿主。

恢复模拟器后必须先复核并恢复本轮诊断设置：

- Playra UI Verify 的“番剧条目加速”从原始“镜像”先后试为直连、ECH，最后确认值为 ECH；应恢复镜像再按需要测试。
- Android 原始 `private_dns_mode` 与 `private_dns_specifier` 都是 `null`。已尝试执行将 mode 写为 `off` 的诊断命令，但 shell 当时失去响应，写入结果未确认；恢复后应检查并还原原始值。
- Wi-Fi 曾执行关闭/开启请求，后续状态未能确认；恢复后先确认 Wi-Fi 开启。未修改宿主代理或 DNS。

原始 APK 与参考项目保持只读。回滚本轮源码使用 `.dart_tool/calendar-sheets-20261109/before/` 中对应文件；该备份保留本轮开始时已有改动，不应通过重置整个工作区回滚。

## 当前交付文件

- 新版隔离验证 APK 已构建：`.dart_tool/calendar-sheets-20261109/Playra-UI-Verify-calendar-sheets-debug-x86_64.apk`。
- 源码指纹：`b5c7e93ebcd668ca136f`；APK SHA256：`caed3d298ff09ee18f185df4ac32520c81b97b77fa610dc3e1d7488e6136c71f`。
- 包名 `com.predidit.kazumi.uiverify`，版本 `2.4.3 (20403)`，ABI 仅 x86_64，供雷电验证，不能当作 ARM 手机正式包。
- 当前模拟器最后实际安装的 Playra 仍是指纹 `38be61c2fd8d3158306b`。本轮新包未安装；不覆盖上一轮不同指纹的原生通过证据。
- [构建与验证收据](../verification/calendar-sheets-20261109/receipt.json)、[测试结果](../verification/calendar-sheets-20261109/calendar-sheets-delivery-fixed.txt)、[静态分析](../verification/calendar-sheets-20261109/calendar-sheets-analyze-final.txt)、[雷电启动日志节选](../verification/calendar-sheets-20261109/emulator-startup.txt)。
- Flutter 示例帧：[390dp 日历](../verification/calendar-sheets-20261109/flutter-calendar-390.png)、[320dp 大字体](../verification/calendar-sheets-20261109/flutter-calendar-320.png)、[800dp 平板](../verification/calendar-sheets-20261109/flutter-calendar-800.png)、[请求失败](../verification/calendar-sheets-20261109/flutter-calendar-failure.png)、[排序弹窗](../verification/calendar-sheets-20261109/flutter-sort.png)。这些是测试渲染图。
