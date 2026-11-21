# Playra 页面设计系统延续（2026-11-19）

> 目标：把首页与日历的淡紫编辑风延续到搜索、分类浏览、追番、我的与详情页，并统一全局 token。
> 实现范围：`lib/presentation/theme/playra_tokens.dart`、`lib/presentation/widgets/playra_backdrop.dart`、`lib/presentation/widgets/playra_page_header.dart`、`lib/pages/discover/search_page.dart`、`lib/pages/discover/browse_page.dart`、`lib/pages/favorites/favorites_page.dart`、`lib/pages/profile/profile_page.dart`、`lib/pages/detail/media_detail_page.dart`

## 1. 设计系统

| Token | Light | Dark |
|---|---|---|
| 页面背景 | `#F3EFF8` | `#1C1726` |
| 卡片表面 | `#FFFFFF` | `#241E30` |
| 卡片浮层 | `#F2EDF8` | `#2B2340` |
| 品牌紫 | `#9966FF` | `#B18CFF` |
| 主文字 | `#16121F` | `#F4EDFF` |
| 次级文字 | `#6B6478` | `#B4A7C4` |
| 分割线 | `#D9CFEA` | `#3B2F50` |

- 全局 `PlayraTokens` 全部切换到淡紫编辑风；播放器保持自身的黑色视频控制层。
- `PlayraBackdrop` 统一提供渐变、装饰纹理、光斑与圆环。
- `PlayraPageHeader` 统一页头：root 页面使用 26sp 大标题，二级页面使用 20sp 标题 + 44dp 圆形返回键。

## 2. 搜索页

- 顶部：44dp 返回键 + 标题「搜索」+ 副标题（当前关键词）。
- 搜索框与「搜索」按钮同行，搜索框占满剩余宽度。
- 结果使用共享 `MediaPosterGrid`（手机 3 列 / 平板最多 6 列）。
- 空状态、加载态、错误态沿用统一组件。

## 3. 分类浏览页

- 顶部：返回键 + 分类标题 +「已加载 N 部内容」。
- 排序 chip：综合 / 最热 / 最新 / 评分，横向滚动。
- 结果网格与搜索页一致，支持下拉刷新与页脚重试。

## 4. 追番页 / 我的页

- 追番页：大标题「我的追番」+ 收藏数量；空状态使用渐变圆形书签图标；有数据时使用同一海报网格。
- 我的页：大标题「我的」+「播放偏好、网络与本地数据」；卡片使用淡紫 token，平板内容最大宽 1000dp。

## 5. 详情页

- 保留 SliverAppBar 大封面与折叠态返回键。
- 页面主体使用 `PlayraBackdrop`，避免底部与相关推荐区域退回纯白底。
- 详情信息、选集 chip、相关推荐全部继承全局 token。

## 6. 实机截图

| 页面 | 截图 |
|---|---|
| 首页（手机 360×800） | `home-phone-20261119.png` |
| 搜索（手机） | `search-phone-20261119.png` |
| 分类浏览（手机） | `browse-phone-20261119.png` |
| 追番（手机） | `favorites-phone-20261119.png` |
| 我的（手机） | `profile-phone-20261119.png` |
| 日历（手机） | `calendar-phone-20261119.png` |
| 详情（手机） | `detail-phone-20261119.png` |
| 首页（平板横屏 1280×853） | `home-tablet-20261119.png` |

## 7. 验收

- `flutter analyze`：0 issue
- `flutter build apk --debug --target-platform android-arm64`：成功
- 手机 360×800 / 平板 853×1280 / 平板横屏 1280×853 截图见 `.analysis/screens/home-redesign-20261117/`
- 页面切换、搜索、分类、追番、我的、详情滚动均无 RenderFlex overflow
