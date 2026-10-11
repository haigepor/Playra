# 未适配二级页面：交付与验证

2026-10-11；仓库 `D:\project\Playra`；开始基线 `acdcbab8`。

呈现代码、局部交互、Web 与 Android 构建已完成。设备与外部接口验收为 PARTIAL；此前检查时没有连接 Android 真机或模拟器。前序播放一体页和发现 Tab 修改与本轮二级页面一并整理交付，本轮没有重做已适配页面。

## 改造结果

1. 搜索及标签搜索：紧凑工具栏、历史管理、条件入口、真实结果封面网格和可移除条件。失败与无匹配分别呈现；查询、ID、排序、分页与历史协议沿用原实现。
2. 以图搜番：上传/链接原生短线 Tab、SVG 预览状态、48dp 以上主要操作、最高相似度分层；保留图片大小限制、URL 校验、忙碌保护、低相似度和回传番名。识别发送说明显式展示。
3. 人物资料与吐槽：局部主题、小图与摘要、资料/吐槽短线 Tab，长资料可滚动；保留真实角色与评论请求、失败重试、头像全屏查看。
4. 首次引导：Playra 标题、当前步骤摘要、进度和固定底部操作；使用约定正文、Android 独有更新步骤、内置规则安装、额外规则确认及最终导航保持原行为。
5. 启动与错误：启动等待不伪造进度百分比，错误有明确原因、实际动作和可展开详情。存储失败页独立于尚未初始化的存储和样式控制器。
6. 图片预览：保留黑底、PhotoView、Hero、缩放和多图分页；新版使用更轻的关闭和翻页控件，关闭区域至少 48dp。

## 验证证据

| 检查 | 结果与边界 |
| --- | --- |
| 21 项目标测试 | 全部通过。覆盖成功空结果/失败/恢复、320/390/760 宽与 1/2 倍字体、筛选取消不写查询、应用与移除标签、历史管理、链接非法输入与 260dp 键盘、大字体结果卡片/角色/引导长文、旧版隔离、故障动作与详情、多图分页及关闭区域，以及完整人物页加载接口与切换真实空评论。最后一项使用测试接口返回，不等同于外部评论接口成功。 |
| 76 项既有回归 | 全部通过。search_parser、bangumi_search_params、interface_navigation、interface_style、mobile_tab_navigation、modern_settings_foundation、modern_profile、modern_player_contract。首次合并运行 94 项通过，随后目标文件增加三项，最终单独运行 21 项通过；这里是 21 + 76 项不同测试的分次记录，不是一次运行 97 项。 |
| 静态分析 | 15 个目标范围，无 error/warning；1 条既有 info：image_search_page.dart 的 `if (action != null) action` 可用 null-aware element 简写。未作无关清理。 |
| UTF-8/SVG/范围 | 严格 UTF-8，无替换字符和 BOM 漂移；3 张 SVG 为 200×130，XML 可解析，无脚本、外链或位图。main.dart 和三份已适配引导设置视图与本轮备份字节一致；player_work_info.dart 仅增加一个 modern 标志。依赖声明/锁文件未变化，git diff --check 通过。 |
| 实际搜索与筛选 | 390/320/760 浏览器布局；从发现进入与返回，320 宽保留返回按钮和输入。草稿选日常后关闭，再打开仍为不限题材；应用后显示条件，再移除条件可同步重新查询。可见主要按钮为至少 48px。 |
| 实际以图搜番 | 上传/链接切换，非法 URL 保持识别按钮禁用，返回原搜索页。键盘缩小由 Widget 测试覆盖，浏览器桌面不代表 Android 软键盘。 |
| 实际首次引导 | 使用约定 → 访问加速 → 添加规则；保留内置规则；未添加额外规则时弹确认。返回安装可留在规则步骤，再选择仍然继续可回发现页。仅操作端口 8942 隔离的开发预览存储。Web 为 3 步，Android 为 4 步。 |
| 实际错误路由 | 无参数打开 /image-preview，显示准确错误与返回首页；动作返回发现页。可展开详情与操作回调另外由 Widget 测试覆盖。 |
| 实际人物资料 | 从作品资料弹层的角色入口进入人物页，外部人物资料 GET 成功并显示真实姓名、配音及资料。观察到头像按钮实际约 88×214px，设定的 132px 仅覆盖内部图片，旧内边距和“查看原图”底栏继续叠加高度；列入后续视觉细修。完整外部评论加载与原图成功仍未验。 |
| Web 构建 | `flutter build web --no-pub --no-wasm-dry-run --target lib/main_home_preview.dart --output build/modern-secondary-preview` 成功；正式 main.dart 平台约束不变。 |
| Android 构建 | `tool/build-android.ps1 -AndroidSdk D:/Android/Sdk` 成功，最终增量构建 17.9 秒；APK 在 build/app/outputs/flutter-apk/app-debug.apk。adb devices -l 无设备。 |

定向测试使用本仓库 `.tooling/bin` 的 vswhere shim、`.tooling/python-tools` 中 CMake/Ninja 与 `.tooling/windows-sdk-libs`，仅配置当前命令进程环境。直接使用系统 vswhere 曾因本地 Unicode JSON 输出失败；不属于页面错误。新增图库测试补齐临时目录模拟后，正常验证原生 PhotoView 分页。

Android 首次直接构建误用 `D:/platform-tools-latest-windows`，报 NDK 28.2.13676358 缺失和许可证未接受。切换到已有完整 `D:/Android/Sdk` 后成功；没有新接受许可证或下载 NDK。构建脚本更新了忽略的 android/local.properties SDK 路径，未修改 Gradle/Kotlin 配置或项目依赖。工具链原有升级提醒仍存在。

本轮浏览器搜索 POST 返回 HTTP 502；页面正确展示“暂时无法获取搜索结果”与重试，不把接口失败写作正常空结果。发现仍加载真实推荐作品，部分封面代理也失败。没有以模拟数据替代业务页面。真实搜索成功卡片由模型绑定与 Widget 布局测试覆盖；外部搜索成功、trace.moe 真实匹配及完整人物评论仍需可用网络复验。人物资料 GET 后续已实际成功，不能继续把整个人物接口写成不可用。

上述测试、分析和构建均为用户要求停止重复验证之前的证据。收尾阶段没有再次运行测试、分析或构建；这些记录不覆盖新会话未来的视觉修改，也不代表所有现有截图都对应最后一次源码编辑。

## 预览与截图

- 实际搜索：<http://127.0.0.1:8942/?rev=secondary-v2#/search/>。
- 实际以图搜番：<http://127.0.0.1:8942/?rev=secondary-v2#/search/image>。
- 引导：<http://127.0.0.1:8942/?rev=secondary-v2#/onboarding>。
- 六组布局参照：<http://127.0.0.1:8941/>，入口 docs/design/modern-secondary-preview.html；布局和结果仅为示例。
- 真实截图：modern-secondary-search.png、modern-secondary-search-back-narrow.png、modern-secondary-filter-narrow.png、modern-secondary-search-error-narrow.png、modern-secondary-image.png、modern-secondary-image-link.png、modern-secondary-onboarding.png、modern-secondary-route-error.png，均位于 docs/verification/。
- 人物入口截图：docs/verification/modern-secondary-character-entry.png，记录的是作品资料弹层的角色列表，不是人物资料页本身，不能用作头像高度修改后的证据。
- 设计参照截图：docs/design/modern-secondary-preview.png。

## 修改文件、影响与回滚

| 文件/目录 | 用途与影响 |
| --- | --- |
| lib/presentation/modern/secondary/secondary_theme.dart | 新版局部范围、空状态、短线 Tab 和故障视图；复用已有主题，不编辑主页面或全局设置主题。 |
| lib/pages/search/search_module.dart、search_page.dart、modern_search_widgets.dart | 新旧路由呈现、紧凑搜索、历史管理和真实卡片；旧页默认保留。 |
| lib/pages/search/search_widgets.dart、search_filter_sheet.dart | 新版排序图标与筛选布局；弹层显式承接局部主题，旧排序图标尺寸保留。 |
| lib/pages/search/search_controller.dart | 增加只读失败状态；在已有 loading 通知前更新，旧 isTimeOut 和 API 契约不变。 |
| lib/pages/search/image_search_page.dart、image_search_widgets.dart | 新版图片输入、空状态和结果层级；文件选择和识别生命周期不变。 |
| lib/bean/card/character_card.dart、lib/pages/info/character_page.dart、character_info_view.dart | 可选 modern 标志、角色局部主题和紧凑人物资料；旧调用默认 false。 |
| lib/presentation/modern/player/player_work_info.dart | 仅向 CharacterCard 传 modern:true，未改变已适配播放页布局。 |
| lib/pages/onboarding/onboarding_page.dart、onboarding_step_layout.dart、steps/disclaimer_step.dart | 紧凑引导呈现和新版欢迎标题，原使用约定正文与步骤逻辑不变。 |
| lib/pages/init_page.dart、route_error_page.dart、error/storage_error_page.dart | 新版准备/故障呈现；已适配设置子树的 RouteErrorPage 沿用原显示。 |
| lib/pages/index_module.dart、lib/bean/widget/image_preview.dart | 引导、错误及图片预览的新旧接线；路由参数与预览手势不变。 |
| assets/images/modern-search-empty.svg、modern-image-search-empty.svg、modern-onboarding-decoration.svg | 三张低对比度装饰线稿，使用项目既有 flutter_svg；无新增依赖。 |
| test/modern_secondary_pages_test.dart、docs/design/modern-secondary-*、本记录及对应截图 | 目标行为保护、设计和验收证据。 |

已有文件在 `.tooling/secondary-redesign-baseline/` 有本轮前备份；搜索控制器的六行增量可依据 `acdcbab8` 的原文件回退。只恢复本轮文件或增量；player_work_info.dart 必须保留前序内容，仅撤掉新增标志。新增文件按上表精确定位，先确认后续编辑，再逐文件移除。禁止整体 reset、清理未追踪目录或覆盖前序播放工作。

## 状态与剩余边界

- DONE：六组呈现、SVG、局部交互、旧版保护、目标与回归测试、浏览器上述场景、UTF-8/范围检查、Web/Android 构建。
- BLOCKED：原生相册权限、实际 Android 安全区/横竖屏/软键盘、双指缩放与图库关闭，当前没有设备。
- BLOCKED：当前网络下真实搜索成功与 trace.moe 匹配场景；图片上传、真实结果选择和完整外部评论需要可用接口复验。人物资料 GET 已成功。
- NEXT：在新会话按交接提示词继续实际页面的颜色、图标、间距和层级细修。连接设备和补接口验收由用户后续安排，当前不追加验证。前序播放 OpenSpec 保持原状态，本轮不创建或归档其他变更。

用户已授权整理既有改动、编写中文提交信息并推送 origin/main，具体提交由本轮收尾完成；提交定位见 `docs/handoff-modern-secondary-polish.zh.md` 和 Git 日志。未修改 AGENTS、Skills、记忆、插件、全局配置或钩子。
