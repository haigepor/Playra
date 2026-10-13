# 影视分类页设计与实现

更新：2026-10-12。项目：`C:/Users/haige/Desktop/Playra`。

## 页面结构

固定主分类、横向题材选择 → 搜索入口 → 精选推荐卡片 → 七天热播榜 → 口碑佳片 → 两个题材栏目 → 猜你喜欢。

电影、电视剧、综艺、漫剧复用同一结构和当前深色主题。题材只展示已返回的真实标签，未接通的分类维持空状态。手机网格常规三列，文字放大减少列数；标题 18 dp、卡片名称 13 dp、辅助信息 11 dp，封面高度为宽度的 1.42 倍。

## 数据边界

- 题材来自 `types`、`tags`，按明确分隔符拆分。页面标题不参与题材判断。主分类继续由真实 `categoryName/categoryId` 决定。
- 精选卡片优先选择 `isRecommend` 的作品，随后参考来源原始 `score`；支持换一部。没有正评分时不制造评分。
- 口碑栏目只展示原始评分有效的已加载作品；两个题材栏目根据当前范围的真实标签组成。切换题材会同时作用于精选、栏目和猜你喜欢。
- 2026-10-12 默认环境实测 `home/modules`、`category/filter/dimensions`、`category/type/listActive`、`category/types`、`video/guessLike` 均返回 HTTP 404。未新增这些端点的公开 SDK 操作。
- 现有 `playCount` 没有近七天时间窗，不能生成七天排名。七天热播榜显示“当前暂无近7天的热播统计”，口碑精选与七天排行明确分开。
- 猜你喜欢是当前分类、题材下的浏览推荐，复用已验证的 `categoryId/pageIndex/pageSize`；当前没有账户画像推荐或已核验的服务端题材参数。

## 自动分页

接近底部 480 dp 且继续向下滚动时请求下一页；只监听外层竖向滚动。横向栏目滚动、上拉刷新和其他主页面不会触发影视分页。

继续复用控制器的请求互斥、取消、代次隔离、身份去重和重复页终止。请求失败后暂停自动重试，保留已有条目，显示手动重试。底部使用 `SliverGrid` 按需构建；不会为了题材筛选预先遍历全站，新增页会继续应用当前题材。

## 修改文件与回滚

- `lib/presentation/modern/miomedia/miomedia_category_view.dart`：题材选择、精选卡片、分类栏目与按需网格。
- `lib/presentation/modern/miomedia/miomedia_home_controller.dart`：题材范围、评分精选和推荐切换状态。
- `lib/services/source/miomedia/miomedia_service.dart`：保留真实题材标签和来源推荐标识。
- `lib/presentation/modern/miomedia/miomedia_browse.dart`：统一封面、辅助信息、网格尺寸与查看更多页面；电影不显示“1集 · 电影大全”。
- `lib/presentation/modern/home/modern_home_view.dart`：接入固定题材导航、精选与滚动分页，保留动漫的原有流程。
- `test/miomedia_display_test.dart`、`test/miomedia_category_test.dart`：分页、首批失败重试、题材一致性、真实身份、大字体布局验收。
- `openspec/changes/integrate-miomedia-content/design.md`：记录真实能力边界与设计决策。

原页面优化前副本：`.dart_tool/miomedia-display-before-20261012/`。
题材与栏目扩展前副本：`.dart_tool/miomedia-category-before-20261012/`。
仅恢复对应文件，不还原仓库中其他已有修改；新建页面、测试和本说明可单独撤回。

## 验证

14 项相关 Flutter 测试通过，覆盖既有内容/播放索引以及新增筛选、推荐、自动分页与首批目录重试。320 dp、2 倍文字大小的推荐卡片和网格无溢出。

新版预览 Web 构建通过；新增模块和测试静态分析无问题。原首页的两条字符串插值提示属于既有代码，本轮没有改动其逻辑。OpenSpec 严格校验通过。

390×844 浏览器实测：电影题材栏、精选、七天榜空状态、口碑和题材栏目正常展示；选择科幻后精选与下方栏目同步变为科幻作品。滚动到尾部的过程中，SDK 请求记录从 11 增至 12，且网格出现新增《复仇者联盟4：终局之战》等作品，证明实际自动分页路径生效。

1280×900 桌面视口保持 760 dp 内容上限，栏目与卡片没有超出主内容区域；电视剧实际展示《逐玉》等作品，综艺展示《哈哈哈哈哈第六季》等作品。综艺条目的现有标签仅包含宽泛类别时，只显示“全部”，不补造真人秀、音乐等题材。

题材未选中态曾继承旧主题浅色背景，已用明确的 WidgetState 颜色覆盖；换推荐图标使用淡紫色，沿用现有 SVG 装饰。真实封面服务器仍可能返回 403/404，现有图片组件提供占位，不视为数据列表加载失败。

最终深色按钮实页截图：`.dart_tool/miomedia-category-before-20261012/movie-dark-final.png`。本轮没有修改 Python SDK 算法、规则文件、平台密钥或用户收藏数据。
