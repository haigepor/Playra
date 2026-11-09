# Playra 影视应用布局重构（2026-11-09）

后续日历、弹窗、首页顶部与空状态的调整，以及当前提交前检查，汇总于 [本次改动与验证](../verification/ui-change-delivery-20261109.zh.md)。本文件末尾链接的原生记录保留其对应源码指纹，不等于最新界面已完成原生复验。

## 依据与取舍

用户已否定此前的玻璃底栏、过多圆角、叠层海报和覆盖封面的大播放按钮。本轮沿用 Flutter、Forui 0.27.7 与现有品牌色，重新组织公共样式及主要内容页面。没有引入另一套组件库。

通过 GitHub 插件搜索了影视、Jellyfin、动漫及 Flutter 自适应客户端，读取了六个项目的 README，并进一步核对四个项目的八份页面或布局源码。研究日期为 2026-11-09；可核对的来源索引保存在 `.dart_tool/cinema-redesign-20261109/research.json`。

| 项目与第一方来源 | 可借鉴之处 | 在 Playra 中的决定 |
| --- | --- | --- |
| [Fladder](https://github.com/DonutWare/Fladder)、[详情骨架](https://github.com/DonutWare/Fladder/blob/develop/lib/screens/shared/detail_scaffold.dart)、[自适应布局](https://github.com/DonutWare/Fladder/blob/develop/lib/util/adaptive_layout/adaptive_layout.dart) | 媒体背景、作品内容与导航分别承担清楚的职责；布局随窗口变化 | 去除首页、日历、追番标题下的装饰插画；保留作品本身的图像；内容宽度按用途约束 |
| [Jellyflix](https://github.com/jellyflix-app/jellyflix)、[响应式导航](https://github.com/jellyflix-app/jellyflix/blob/main/lib/components/responsive_navigation_bar.dart) | 小屏底栏、中等宽度导航轨、宽屏侧栏 | Playra 使用自己的 600／1120dp 导航断点，保留当前路由和页面状态 |
| [Streamyfin](https://github.com/streamyfin/streamyfin)、[首页轮播](https://github.com/streamyfin/streamyfin/blob/develop/components/home/HomeHeroCarousel.tsx) | 轮播几何按当前窗口重新计算，支持旋转和分屏 | 推荐区改成单一横向滑动层；移除景深缩放、重阴影与相邻海报叠压；使用当前内容区宽度 |
| [PiliPlus](https://github.com/bggRGjQaUbCoE/PiliPlus)、[主导航](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/pages/main/view.dart)、[播放页](https://github.com/bggRGjQaUbCoE/PiliPlus/blob/main/lib/pages/video/view.dart) | 平板导航和播放布局单独处理，关注可用宽高关系 | 导航、普通播放画布与全屏状态分别布局；不以卡片圆角裁切视频 |
| [Miru](https://github.com/miru-project/miru-app) | 多来源内容在统一界面中组织 | 保留来源、搜索与播放业务，统一其外层布局与控件 |
| [Dartotsu](https://github.com/aayush2622/Dartotsu) | 动漫发现、收藏与播放属于连续的内容流程 | 作为产品范围对照；未把其界面、框架或配色直接移入 Playra |

以上是源码和项目材料支持的结构参考；具体间距、断点和信息层级是根据 Playra 当前内容作出的设计选择。没有用第三方项目的星数替代适用性判断，也没有将第三方应用描述为已经在本机运行验证。

## 样式的统一所有者

- Forui 负责颜色、字体、控件状态、按钮、列表项、页签、导航及弹层表面。
- `playra_design.dart` 负责现代界面的 Forui 主题定制；普通页签统一为平直底线样式，不再套一层圆角底板。
- `PlayraLayout` 负责视口断点、页面留白、内容宽度和响应式列数。列数使用实际内容区宽度与字号计算，不能只依据设备型号。
- `PlayraMedia` 负责视频和海报上的固定对比色。视频覆盖层不能直接使用浅色页面正文色。
- 公共卡片增加可指定边界圆角的能力；底部弹层仅保留上侧圆角，避免底部也出现圆角缺口。

| 边界 | 处理原则 |
| --- | --- |
| 页面背景、贴边底栏、页签底板、视频画布、全屏画面 | 直角；不增加外层圆角容器 |
| 独立内容卡片、推荐封面、海报缩略图 | 使用对应 Forui／Playra 语义圆角；避免重复嵌套边框和圆角 |
| 按钮、输入框、菜单、设置列表 | 优先使用 Forui 控件的 style；自定义内容使用同一组 token |
| 头像、进度柄、拖动柄 | 由组件本身的形状职责决定，不机械改成方形 |

## 尺寸规则

所有宽度均为 Flutter 逻辑像素，不是截图的物理像素。

| 可用宽度 | 导航与留白 |
| --- | --- |
| 小于 600dp | 贴边底栏；页面横向留白 16dp；键盘出现时隐藏底栏 |
| 600–839dp | 88dp 导航轨；页面留白 24dp |
| 840–1119dp | 导航轨；页面留白 32dp；设置页可显示主从双栏 |
| 1120dp 及以上 | 208dp Forui 侧栏；内容受用途宽度约束 |

搜索与日历在空间足够时显示双列，追番可显示多列；字号增大时减少列数。表单、阅读内容和媒体目录分别使用既有的 760／880／1120dp 宽度 token。短横屏不再仅因高度较矮就套用窄手机的密度规则。

## 按页面族执行

| 页面族 | 本轮执行的布局与细节 |
| --- | --- |
| 全部现代页面壳层 | 去掉玻璃背景采样和悬浮胶囊底栏；小屏贴边底栏，宽屏导航轨／侧栏；改变宽度时保留页面状态 |
| 首页、动漫、影视、分类频道 | Forui 页签承担频道切换；主频道可横向访问，当前子频道保持可见选中状态，保留“更多”快捷菜单；推荐轮播改为单层内容；统一页面留白 |
| 首页推荐卡 | 去掉景深、重阴影、装饰徽章及重复操作；原先两个按钮都进入详情，现统一标为“查看详情” |
| 搜索与搜索结果 | 分类使用公共 Forui 受控页签；小屏自然增长的结果列表，平板双列；保留 IME、清空、频道和分页行为 |
| 日历与季度选择 | 筛选页签统一；宽屏双列放送卡；窄屏大字体时日期操作另起一行；季度卡按缩放后的文字高度、间距和边框计算高度，修复 1px 溢出 |
| 追番、收藏 | 平直页签；卡片和列表列数共用宽度／字号规则；保留分类、搜索、排序、续播与状态修改 |
| SDK 播放详情 | 视频区域直角；播放前预览与正常视频共用矩形边界；正常尺寸播放按钮位于左下方，无可播剧集时显示文字状态；播放源栏使用真实 Forui 列表项；大字体允许选集减少到单列 |
| 传统播放与播放器附属页 | 沿用现有原生播放、横竖屏和画中画状态；公共页签、弹层、按钮、选集及媒体 token 共同生效 |
| 我的与设置子页 | 共用新导航；设置项使用真实 Forui 列表项框架；现代设置主从布局从 840dp 开始，避免窄窗口硬塞两栏 |
| 历史、离线缓存 | 阅读宽度与页面留白使用公共 token；保留滚动、筛选、编辑及下载业务 |
| 评论、规则、资料及公共对话框 | 收敛剩余非上游展示代码的字号和圆角字面量；评论表面减少圆角；沿用公共控件和 token |
| 引导、错误、日志、人物资料、以图搜索、规则表单 | 通过公共主题、控件及弹层消费统一规则；已有聚焦回归继续验证长文、输入、返回、错误和大字体行为 |

没有机械替换所有数字：图片比例、画布尺寸、图形坐标和业务数据不等于样式 token。上游组件展示源码单独保留。页面盘点及剩余数值分类见 `.dart_tool/cinema-redesign-20261109/page-inventory.json` 与 `remaining-layout-literals.json`。

## 验证与实际限制

验证日志、原始截图、隔离构建资料及逐文件修改前副本保存在 `.dart_tool/cinema-redesign-20261109/` 和 `.dart_tool/emulator-ui-20261108/`。最终原生结果与截图见 [雷电运行验证](../verification/emulator-ui-20261108.zh.md)。

正式私有 Lumina profile 尚未恢复；验证包继续使用此前授权的隔离环境及匹配的历史 receipt。不能将隔离验证包的成功表述为正式 release 或当前私有输入已恢复。
