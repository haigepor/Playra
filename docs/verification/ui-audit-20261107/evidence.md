# Playra UI 审查证据

2026-11-07，源码基线 `57c63c29`，声明版本 2.4.3。本文件只记录本轮观察，不替代原生功能验收。

## 构建与环境

成功命令：

```powershell
flutter build web --no-pub --target lib/main_home_preview.dart --output build/ui-audit-preview --no-wasm-dry-run
```

输出：`Built build\ui-audit-preview`，编译日志报告 104.4 秒。预览使用仓库 `tool/web_backend/server.cjs`，端口 8947，根目录指向本次构建。审查结束后关闭服务。

已连接 Android 设备安装版本为 2.4.2，设备锁屏，未解锁、未安装当前版本、未把旧版本作为当前行为证据。

## 当前 Web 实测

| 路径 / 操作 | 观察 |
| --- | --- |
| 390×844，发现 | 页面可见；十项频道横向排列；排期按钮 32×32；显示“当前平台尚不支持 Lumina”与重试；推荐区未出现内容 |
| 发现 → 日历 | 显示“当前仅保留 Lumina 数据源”“放送日历所需的数据源已移除”；与手机分页静态分支不同 |
| 追番 | 空态可达，包含去发现操作；未使用真实收藏数据 |
| 我的 | 观看概况、历史/下载/搜索快捷入口、偏好、同步、关于可达 |
| 我的滚动到底 | 版本文本与底部导航覆盖区重叠，关于行底部也落入覆盖区；边界见下表 |
| 搜索初始页 | 搜索输入、搜索按钮、全部/剧集筛选和空态可见；没有执行网络检索 |
| 搜索 320×568 | 搜索按钮边界约 x=250,y=72,w=54,h=32；全部/剧集按钮 h=32；未作软键盘或大字体验收 |
| 设置首页 | 11 类入口存在；实际打开播放、操作、下载、外观、界面、同步、网络、更新、存储等页 |
| 播放设置 | Web 分支解释浏览器解码，并显示适用选项；原生 MPV 功能未验证 |
| 外观设置 | 新版固定深色说明、系统字体开关存在；没有变更设置 |
| 界面设置 | 页面样式、默认启动页、默认追番布局存在；没有变更设置 |
| 同步总览 | WebDAV 未配置，存在设置入口 |
| WebDAV 管理/服务器表单 | 未配置状态、禁用同步项、三项输入及保存测试入口可见；未填写凭据、未提交、未同步 |
| 网络设置 | Web 网关/代理说明可见；未修改代理 |
| 历史、下载 | 各自空态可达；没有创建、删除或下载内容 |
| 1440×900 | 个人页仍采用最大宽 440 的底部导航；设置有类别侧栏，关于与帮助可达 |
| 帮助 | “同步与更新”仍提及 Bangumi 与 WebDAV 可配置；当前 Bangumi 设置路由却是来源停用说明 |

### 个人页底部坐标

390×844，滚动到底后，来自 Flutter Web semantics 元素的浏览器边界：

| 元素 | x | y | 宽 | 高 |
| --- | ---: | ---: | ---: | ---: |
| 悬浮导航 | 16 | 772 | 358 | 60 |
| 关于应用 | 20 | 729 | 350 | 49 |
| Playra · 2.4.3 | 20 | 802 | 350 | 18 |

边界相交已确认；没有据此推断整行“关于”完全无法点击。其下边缘约 6px 位于导航区域，版本文本位于导航区域内。

### 颜色计算

从源码颜色做 sRGB 相对亮度换算，比较 `(较亮亮度+0.05)/(较暗亮度+0.05)`：

| 文字 / 背景 | 计算值 | 用途 |
| --- | ---: | --- |
| `#FFFFFF` / `#A7B7FF` | 1.93:1 | 当前深色主按钮 |
| `#182142` / `#A7B7FF` | 8.13:1 | 已有 primaryForeground token |

这是源颜色计算，不是对截图中每个抗锯齿像素的测量。

## 截图与日志

- [发现页，390×844](home-390.png)：本轮当前源码预览，缺源/空内容状态。
- [搜索页，390×844](search-390.png)：本轮当前源码预览，初始状态。
- [浏览器警告与错误](browser-console.txt)：字体连接错误、第三方请求 CORS 错误等；未把它们当作 Android 故障证明。

截图先通过当前 Codex 目录的 `image-guard/image_guard.py preview`，再读取返回的预览路径；本轮只查看两张预览。

两次 UI 自动化定位超时发生在精确文字选择器与合并的 Flutter 语义不一致时；重新读取语义树并调整定位后继续成功。没有把自动化超时直接判定为页面坏掉。

## 未验证项

当前 Android 包、成功播放与续播、原生日历加载、有内容收藏/历史、真实下载和同步、iOS、原生 Windows、大字体、系统软键盘、TalkBack/VoiceOver、减少动画的实际视觉表现、全页面宽屏覆盖。

## 源码证据入口

- `lib/presentation/widgets/playra_controls.dart`：按钮 172～174 行、文字色 182 行、图标按钮默认尺寸 311 行。
- `lib/presentation/theme/playra_tokens.dart`：统一尺寸、颜色、字体和动画约定。
- `lib/presentation/modern/modern_shell.dart`：底部悬浮导航与 extendBody。
- `lib/presentation/modern/profile/modern_profile_view.dart`：24 底部留白与重复同步入口。
- `lib/presentation/shared/tab_shell.dart`、`modern/modern_tab_pages.dart`、`lib/pages/timeline/timeline_module.dart`：日历入口分叉。
- `lib/presentation/modern/home/modern_home_view.dart`：十项首页频道与布局分支。
- `lib/presentation/modern/pages/content_search_screen.dart`：搜索两层顶部、筛选与结果布局。
- `lib/presentation/modern/pages/sdk_player_detail_page.dart`：当前作品播放主页面。
- `lib/pages/settings/settings_module.dart`、`lib/pages/search/search_module.dart`、`lib/pages/info/info_module.dart`、`lib/pages/plugin_editor/plugin_module.dart`：当前路由与兼容入口。

页面判定以本轮源码与实际运行记录为准，旧 README、旧截图或文件仍然存在不构成功能仍然可达的证明。
