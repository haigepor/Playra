# 历史、下载、规则与同步页面设计实施记录

日期：2026-10-15。按四个可独立回退的视觉切片实施；追加处理奖杯、页头裁切和作品标签反馈。使用现有 Flutter、Material、主题和状态模型，没有引入新 UI 框架。

## 方向与验收

采用已有的影院纸张材质作为唯一视觉特征，信息层级优先于装饰。另一种全页大背景方向会干扰长列表和表单，因此选择一次介绍区或初始空态的小范围材质。正文、规则列表、下载任务保持纯色。语义颜色取自现有主题；功能动作沿用原控件和回调。

验收包括：320/390/1440宽；既有2倍字号测试；真实来源与SDK身份；历史搜索/缓存来源、下载展开与状态、规则筛选/选择/排序、同步配置入口和表单宽度。空白、未配置与错误状态不能被装饰冒充成功。

## 落地结果

| 范围 | 设计与行为 |
|---|---|
| 历史 | 880最大内容宽度；搜索14圆角、筛选固定形状；日期标题、独立14圆角记录卡；集数与观看位置为第二阅读层，来源与时间为第三层。保留真实续播、收藏、滑动删除及快捷键。初始空态使用生成的电影票；过滤无结果保留轻量提示与重置。 |
| 下载 | 对齐内容栏，作品总览和分集任务分开；收起时显示作品进度，展开后显示分集进度。下载不再同时出现圆环和线条；六态使用SVG和真实状态文字。小屏操作下置，48最小触控区；长错误信息最多两行。保留真实任务回调、确认删除和离线播放。 |
| 规则 | 简介改为“来源与 SDK”，添加规则为主操作，仓库为次操作。分类下拉菜单取代重复分类chips；保留更新筛选、批量操作与排序规则。卡片突出名称、站点、SDK、状态，版本/适配器/性能为辅助信息。 |
| SDK身份 | 复用现有 `PlaybackSourceGroup.fromPlugins` 和 `playbackSdkId` 的受管理标记及运行路由验证。当前内置DM84/MXdm/akianime/moonci归属AniFive，适配器分别anifive-a/b/c/d。未登记规则显示“独立规则 · 未关联 SDK”，不按名称或HTTP模式猜SDK。搜索支持已登记SDK名称。没有修改SDK登记、来源执行或providerId。 |
| 同步 | 统一SVG服务身份、状态文字、说明和48高操作；Bangumi/WebDAV分别使用书签和设备符号。介绍区一张设备影片卡材质；配置表单无背景。共用布局保留调用方640/720宽度，总览最多760。未配置/未连接/已开启等状态沿用真实服务判断。 |
| 奖杯 | 图像由32×36缩至22×25；加3px内边距、轻薄深色半透明衬底、细边与小阴影，外框28×31，左上仍内缩4。金银铜共用处理；解码66宽，名次语义保持。 |
| 页头背景 | 使用BoxFit.contain完整比例显示，去掉54/48高容器内的按宽放大裁切和纵向淡出。素材缩入页头可用空间，保留透明通道与低透明度。 |
| 线路选择 | 每个站点独立14圆角分组，站名/真实线路与集数/选项分层；当前线路用淡紫背景、边框与“当前”标记；获取失败使用错误色文字和明确重试按钮，空目录单独说明。保留SDK返回顺序、真实线路身份和原重试/选线回调。 |
| 作品标签 | 新版主题明确Chip背景/文字/选中/悬停/禁用色，修复强制暗色页面继承浅色Chip造成的白底浅字。默认文字#EDF0F8、底#1B202C；12字号与10圆角；展示层合并重复标签，保留原资料和标签搜索。 |

## 素材与提示词

新增三张透明PNG：`assets/images/modern-history-art.png`、`modern-offline-art.png`、`modern-sync-art.png`，均2172×724 RGBA，角落alpha=0，约0.93–1.00MiB。内置image_gen基于已认可原图进行材质迁移。完整提示词见 [utility-pages-imagegen-prompts.md](utility-pages-imagegen-prompts.md)，原始认可背景提示词正文没有改动。

新增13枚24×24 SVG：history、offline、rules、sdk、synchronization、collection、devices、pending、resolving、downloading、paused、failed、completed。文件为 `assets/images/modern-utility-<name>.svg`；1.7线宽、圆角端点、小面积浅填充；运行时跟随主题着色，排除重复读屏。

`UtilityPageIntro` 承担单次页头装饰；`UtilityMaterialArtwork` 裁去原图透明左侧以显示空态主体；`UtilitySvgIcon` 统一小图标。它们不参与业务状态判断。图片限制解码尺寸，不在记录或任务卡内重复铺设。

## 文件与回退

| 路径 | 目的 |
|---|---|
| `lib/pages/history/history_list_view.dart`、`history_record_tile.dart` | 历史布局与空态 |
| `lib/pages/download/download_page.dart`、`download_widgets.dart` | 下载布局、状态和进度 |
| `lib/bean/card/rule_card.dart` | 规则卡与可选sdkLabel展示 |
| `lib/pages/plugin_editor/plugin_view_page.dart`、`rule_management_widgets.dart` | 规则头部、筛选与SDK真实映射 |
| `lib/pages/settings/sync/sync_settings_page.dart`、`sync_settings_widgets.dart` | 服务卡、配置入口、表单宽度 |
| `lib/presentation/modern/secondary/utility_page_art.dart` | 新共享视觉小组件 |
| `lib/presentation/modern/miomedia/miomedia_browse.dart`、`widgets/modern_page_art.dart` | 奖杯衬底与完整页头构图 |
| `lib/presentation/modern/player/sdk_source_widgets.dart`、`pages/modern_player_detail_page.dart` | 追加线路面板设计；只修改视图部分 |
| `lib/presentation/modern/home/home_theme.dart`、`player/player_work_info.dart` | 新版Chip主题与资料标签 |
| `assets/images/modern-utility-*.svg`、三张新PNG | 本轮资产 |
| `docs/design/utility-pages-preview.html`、`ui-refinement-preview.html` | 交互示意与细节预览 |

15个已有Dart文件和原细节预览的修改前副本位于 `.dart_tool/utility-pages-backup-20261015/` 对应相对路径。新增文件可按引用单独回退；有并发业务修改时只逆转本次差异，不整文件覆盖或整体重置。工作区原有接口、规则迁移、播放器业务与平台文件改动不属于本次视觉任务。

## 已取得的验证证据

- **DONE**：相关静态检查分批覆盖14个Dart文件，均无问题；新增/修改文本严格UTF8、无BOM/替换字符；SVG XML/viewBox检查通过。
- **DONE**：最终Chip主题加入后，5个既有测试文件共44项通过，覆盖设置、首页、日历、追番、播放器合同，以及320宽和放大字体；SDK登记防误分组测试3项通过。此前二级页面套件也通过；重叠用例不累计。
- **DONE**：设计预览在320、390、1440宽的四个页面无横向溢出、素材加载完整、控制台无错误。DOM驱动的示例筛选、展开/暂停、启用状态切换和WebDAV表单显隐通过；示例不写入真实数据。
- **DONE**：实际Flutter页面390宽已确认历史/下载初始空态，规则真实列表和同步两张服务卡。通过可访问节点进入WebDAV页及服务器表单；真实配置未保存、未发送授权请求。
- 构建、最终SDK版页面与追加图形的收尾结果在下方补充。

## 验证边界

HTML是设计示意，数据与部分交互仅用于审阅，不能替代Flutter真实业务。历史/下载当前没有真实记录，未创建或删除用户任务来凑验收。Android/iOS未做真机验收；大图传输预算可另行压缩。当前应用的接口/封面502、404仍是既有工作范围，不在本次修复中。

### 追加线路验证
- **DONE**：`miomedia_sdk_ui_test.dart`、`sdk_source_switch_episode_test.dart`共10项通过；与44项页面回归及3项SDK分组测试合计57个不重复用例。
- 分批analyze的最后两个并发修改文件仍有3条既存info：两个单行if缺少大括号，以及一个collection-if建议使用null-aware元素；修改前备份已包含相同结构。这些位置不属于本次视图变更，未改写并发业务。没有新的error/warning；最终Web构建结果见收尾记录。
- 真实规则页可访问树显示AniFive及anifive-a/b/c/d；分类菜单切换影视后显示0/4、保留“显示全部规则”恢复入口。输入检索未作为本次浏览器通过证据；其条件由源码核对，预览演示单独验证。

### 最终收尾结果
- **DONE**：最终 `flutter build web --no-pub --no-wasm-dry-run` 成功（94.8s），覆盖追加的线路站点分组、当前标记和重试按钮。
- **DONE**：五类预览（历史/下载/规则/同步/线路）在320、390、1440宽均无横向溢出，全部图片加载；320宽1.6倍文字也无横向溢出。预览控制台0错误/0警告；线路示例可切换当前项。
- **DONE**：奖杯预览测量图22×25、衬底28×31；页头图片object-fit为contain。实际发现页390截图确认完整缩放的页头图，见 `.dart_tool/utility-app-header-final-390.png`。榜单实际内容仍受接口加载状态影响，不把示例预览当作完整播放验收。
- **DONE**：真实规则页390截图见 `.dart_tool/utility-app-rules-sdk-final-normal-390.png`，SDK和适配器可读；分类菜单筛选影视后显示0/4并能恢复全部。真实同步流程进入服务器表单，未提交配置。
- **NEXT**：Android/iOS真机；有真实历史和下载数据时补充全流程验收。无新增数据接口或执行契约变更，无待实施设计项隐藏在本次交付中。
