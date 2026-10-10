# Flutter 放送日历与季度选择组件研究

研究日期：2026-10-11。范围：组件选型、季度弹层交互与现有数据适配；本研究不安装依赖，不修改应用代码。

## 结论

本次截图的问题适合用 **Flutter 官方 `YearPicker` 年份网格 + 现有 `shadcn_ui` 基础组件 + 独立季度业务面板** 解决。保留一个弹层，年份网格在同一位置切换显示，避免年份下拉菜单遮挡季度卡片。这个组合使用成熟组件承接年份交互，同时保留准确的四季度语义。

如果后续把页面扩展成“真实日期、周/月切换、事件标记”的日历，优先评估 `table_calendar`。当前的“按星期列出季度番剧”与按具体日期列出某一集的实际更新，是两种数据模型，不能靠换组件自动等价。

研究的库均未提供现成 `QuarterPicker`。`calendar_date_picker2` 有年/月视图，但默认用于日期导航；Syncfusion 可进行真正的月/年选择，也仍需季度映射或独立面板。无需为四个季度直接引入完整商业日历。

## 当前项目和截图问题

- `pubspec.yaml` 声明 Flutter `3.47.6`、Dart `>=3.10.0 <4.0.0`；本机 `dart --version` 实测 `3.13.5`。`pubspec.lock` 固定 `shadcn_ui 0.57.1`、`intl 0.20.3`。本地 `flutter_localizations` 要求 `intl ^0.20.3`。
- `ScheduleEntry` 保存作品、星期、可确认的北京时间与地域；`calendarSeason` 归一化为 `1 / 4 / 7 / 10` 月起始日期。数据层已具备独立季度模型，不需要由日期组件重新定义。
- 新截图的年份浮层覆盖季度内容，年份列表又形成第二层滚动区域；字号和卡片体积偏大，层级集中在大面积背景块，不能快速扫描。
- 这些是弹层结构、信息密度和状态切换问题。组件库可提供年份网格、焦点和滚动行为；最终的布局比例、暗色主题与季度选择仍需定制。

## 官方组件能力比较

以下平台指发布者声明支持 Android、Web、Windows，不表示本项目已经安装并完成三个平台的运行验收。

| 组件 | 已核验版本 | 日期/周/月 | 年/月选择 | 四季度选择 | 对本项目的适配 |
| --- | --- | --- | --- | --- | --- |
| Flutter `YearPicker` | 项目 SDK 自带 | 只处理年份 | 可滚动年份网格，直接回调所选年 | 无；组合独立季度面板 | 本次最合适，零新增依赖 |
| `shadcn_ui` `ShadCalendar` | 已安装 `0.57.1` | 日期单选、多选、范围 | 标题标签或月/年下拉 | 无；`raw` 也不是季度插槽 | 继续复用主题、按钮、容器；不强行改日期网格 |
| `table_calendar` | pub 最新 `3.3.0` | 月、两周、周；事件标记 | 无独立年份网格 | 无 | 未来真正的周/月事件日历优先候选 |
| `calendar_date_picker2` | pub 最新 `4.0.0` | 单选、多选、范围；日/月/年/滚动视图 | 有网格，但选择月/年默认返回日视图 | 无；月份网格固定 12 项 | 常规日期弹层适合，季度需额外改造 |
| Syncfusion `SfDateRangePicker` | pub 最新 `35.1.39` | 日期、范围、多选；多视图 | 年视图显示月份，十年视图显示年份；关闭视图导航后可以直接选择 | 无 | 月/年直接选择能力强，但本次成本偏高 |

官方来源：[YearPicker API](https://api.flutter.dev/flutter/material/YearPicker-class.html)、[shadcn_ui 0.57.1](https://pub.dev/packages/shadcn_ui/versions/0.57.1)、[TableCalendar](https://pub.dev/packages/table_calendar)、[CalendarDatePicker2](https://pub.dev/packages/calendar_date_picker2)、[Syncfusion DatePicker](https://pub.dev/packages/syncfusion_flutter_datepicker)。

## 定制边界

### Flutter YearPicker：年份网格承接成熟交互

`firstDate` / `lastDate` 控制可选年份，`selectedDate` 表示所选年，`onChanged` 在年份选择时回调。它没有季度模式；季度禁用应在业务面板判断。不要使用已弃用、已无作用的 `initialDate`。来源：[YearPicker API](https://api.flutter.dev/flutter/material/YearPicker-class.html)。

建议将其放在有明确高度约束的同层区域，通过局部 `Theme` / `DatePickerTheme` 对齐暗色、选中态与文字，而不是再次打开年份 Dropdown。如果设计要求完全改变网格结构，则需自定义年份网格，不能误称为只改主题。

### 已有 ShadCalendar：保留设计体系，不改造成季度网格

根代理核验本地 `shadcn_ui 0.57.1` 源码：`ShadCalendarVariant` 为 single / multiple / range；`captionLayout` 为标签、双下拉、月份下拉或年份下拉；日网格按星期列组织，没有公开的年份网格或季度网格替换 builder。`ShadCalendar.raw` 增加参数组合，不能凭此替换成四季度布局。官方示例：[Calendar](https://mariuti.com/flutter-shadcn-ui/components/calendar/)。

因此季度弹层复用 `ShadButton`、图标按钮、主题和弹层容器即可，日期日历本体不是必选依赖。此处版本判断以项目已安装源码为准，未把官网最新示例当作固定版本保证。

### table_calendar：适合日期事件，不提供年份与季度弹层

`CalendarFormat` 只有 month / twoWeeks / week。`CalendarBuilders` 可定制选中日、今日、星期标题、事件标记等；`eventLoader(day)` 返回该日期的事件。`firstDay` / `lastDay` 限制边界，`enabledDayPredicate` 限制可选日期。来源：[格式枚举](https://pub.dev/documentation/table_calendar/latest/table_calendar/CalendarFormat.html)、[Builders](https://pub.dev/documentation/table_calendar/latest/table_calendar/CalendarBuilders-class.html)、[TableCalendar API](https://pub.dev/documentation/table_calendar/latest/table_calendar/TableCalendar-class.html)。

本项目可把它用于未来紧凑周条、月度追番分布、当天数量标记；季度选择仍由独立组件负责。外部内容 `PageView` 与它的周翻页必须统一状态，避免两个横向手势互相抢占。

### calendar_date_picker2：月/年视图不是独立的季度选择接口

官方 `4.0.0` 配置支持 `dayBuilder`、`monthBuilder`、`yearBuilder`，及日/月/年的 selectable predicates。`calendarViewMode` 指初始视图，不是“最终选择只精确到季度”的模式。来源：[Config API](https://pub.dev/documentation/calendar_date_picker2/latest/calendar_date_picker2/CalendarDatePicker2Config-class.html)。

本研究还直接下载并在内存读取 pub 发布的 `4.0.0` 源码包，核验：

- `_handleMonthChanged`、`_handleYearChanged` 都将 `_mode` 改为 day；它们更新显示月份，不直接完成日期值选择。
- `_MonthPicker` 的 `GridView.builder` 固定 `itemCount: 12`。
- `monthBuilder` 改单元内部外观。返回空 Widget 不会把 12 个网格位置重排为 4 个季度；月份索引和导航语义仍然存在。

复核入口：[官方源代码](https://github.com/theideasaler/calendar_date_picker2/blob/main/lib/src/widgets/calendar_date_picker2.dart)、[发布包元数据与 archive_url](https://pub.dev/api/packages/calendar_date_picker2)。

因此只换 builder 无法正确变成四季。拦截 `onDisplayedMonthChanged` 作为“季度选择”也会把普通翻页误认成用户确认；如果 fork 修改内部网格和回调，后续版本合并成本高于独立季度组件。

### Syncfusion：直接月/年选择成立，但没有季度模式

`DateRangePickerView.year` 显示一年内月份，decade 显示年份，century 显示十年段。默认点击用于下钻导航；`allowViewNavigation: false` 后才允许在这些视图中直接选择。来源：[Views](https://help.syncfusion.com/flutter/daterangepicker/views)、[allowViewNavigation](https://pub.dev/documentation/syncfusion_flutter_datepicker/latest/datepicker/SfDateRangePicker/allowViewNavigation.html)。

`cellBuilder` 可以定制月/年单元；`minDate` / `maxDate` 可限制日期边界，`selectableDayPredicate` 属于日粒度约束，不能默认替代季度禁用。可用 `SfDateRangePickerTheme` 对齐背景、选中颜色、文本。来源：[cellBuilder](https://pub.dev/documentation/syncfusion_flutter_datepicker/latest/datepicker/SfDateRangePicker/cellBuilder.html)、[日期约束](https://help.syncfusion.com/flutter/daterangepicker/date-restrictions)、[主题 API](https://pub.dev/documentation/syncfusion_flutter_core/latest/theme/SfDateRangePickerThemeData-class.html)。

即使限制只选 `1 / 4 / 7 / 10` 月，也不会自然变成四个季度单元。它更适合产品明确需要月、年、范围、多视图等完整能力时采用。

## 版本、依赖与许可

| 库 | 许可/成本 | 本项目版本约束核验 |
| --- | --- | --- |
| `YearPicker` | Flutter SDK 自带，无新增包 | 与项目使用同一 SDK |
| `shadcn_ui 0.57.1` | MIT，已安装 | 无需升级即可继续组合基础组件 |
| `table_calendar 3.3.0` | Apache-2.0 | SDK `>=3.0.0 <4`；`intl >=0.20.3 <0.21`，与当前锁定版本没有已知直接冲突 |
| `calendar_date_picker2 4.0.0` | Apache-2.0 | changelog 要求 Flutter 3.47+；增加 `material_ui ^1.0.0`；不能只根据宽松 environment 宣称兼容 |
| Syncfusion `35.1.39` | 商业或 Community License | SDK `^3.7.0`、Flutter `>=3.35.1`、`intl >=0.18.1 <0.21`；引入 `syncfusion_flutter_core` |

版本约束来自本次 live 请求的 [TableCalendar 包 API](https://pub.dev/api/packages/table_calendar)、[CalendarDatePicker2 包 API](https://pub.dev/api/packages/calendar_date_picker2)、[Syncfusion 包 API](https://pub.dev/api/packages/syncfusion_flutter_datepicker)。许可证来源：[TableCalendar](https://pub.dev/packages/table_calendar/license)、[CalendarDatePicker2](https://pub.dev/packages/calendar_date_picker2/license)、[Syncfusion](https://pub.dev/packages/syncfusion_flutter_datepicker/license)。

`calendar_date_picker2 4.0.0` 的 [changelog](https://pub.dev/packages/calendar_date_picker2/changelog) 与 pubspec 的宽松最低 Flutter 版本不同；其新依赖 `material_ui` 最新 `1.6.0` 要求 Flutter `>=3.47.0`、Dart `^3.13.0`。当前本机 Flutter `3.47.6`、Dart `3.13.5` 满足这两个门槛；完整依赖图是否能解析仍需后续 `pub get` 验证，不能由版本门槛推导为本项目已安装通过。来源：[material_ui 元数据](https://pub.dev/api/packages/material_ui)。本次未执行依赖解析或新库跨平台构建。

Syncfusion 包 License 与官网 Community 页面列出的资格条款不完全一致；官网还包含员工人数、融资条件及开源项目注册要求。实际接入前应确认项目资格和适用授权，不能把源码可下载等同于无需授权。来源：[包 License](https://pub.dev/packages/syncfusion_flutter_datepicker/license)、[Community License](https://www.syncfusion.com/products/communitylicense)。

## 建议的季度面板结构

这是结合当前截图与组件能力提出的设计建议，不是库内置行为：

1. 标题行“选择季度”，小号当前选择说明，如“2026 年 · 秋季”，关闭按钮使用清楚的灰白图标。
2. 主体高度稳定，默认显示“上一年 ← / 2026 年 / → 下一年”，下方四个紧凑季度选项。季度名与 `1月 / 4月 / 7月 / 10月` 双层文字即可；不再使用大面积卡片装饰。
3. 点击中间年份，在原主体位置切换为 `YearPicker` 网格；同一个弹层显示“选择年份”和返回箭头。选择年份后回到季度面板，不额外弹出覆盖菜单。
4. 季度使用 2×2 布局或紧凑横向四选项，选中项用淡紫底、细边框和小勾标记；当前季度与已选季度分别标识，未来季度禁用。
5. 点击季度形成唯一提交事件，再关闭弹层并加载数据；切换年份只是暂存状态，不立即请求远程季度数据。
6. 底部固定“当前季度”快捷按钮；移动端保留 SafeArea，宽屏使用受限宽度的居中弹层，大字体允许主体滚动而不截断按钮。

建议逻辑状态：`view: quarters | years`、`draftYear`、`selectedSeason`、`currentSeason`。年份切换保留原已选季度标识；禁用规则为 `quarterStart > currentSeason`，不能简单用“季度最后一天 > 今天”禁用当前季度。

继续复用 `CalendarSeasonPicker` 作为 UI 所有者与 `calendarSeason` 作为归一化函数。页面只接收季度值；作品分类、排序、历史、追番与网络请求继续由现有 controller / service 处理，不塞进组件 builder。

## 放送日历后续能力和验收边界

如果新增月度日历，先新增日期事件适配器，明确区分“周期放送预期”与“具体日期已确认更新”。`ScheduleEntry.weekday` 和 `time` 只能支持周期预测；未知时间、未确认剧集、停播不能补成实际更新事件。

接入后的验收至少包含：年份网格不会覆盖季度选项；当前年/历史年/未来季度边界；跨年往返与取消不提交；320 宽和大字体不溢出；Android 安全区；Web/Windows 鼠标滚动与键盘焦点；日期/季度切换只有一次业务提交；反复切换后的请求取消和缓存正常。

本研究完成官方能力、发布版本及当前项目约束比对。没有对新库作安装或运行通过声明；下一阶段只需先验证 `YearPicker + Shad` 的紧凑弹层，待日期事件模型明确后再决定整页日历依赖。

布局概念稿：`docs/design/season-picker-component-proposal.svg`，展示季度与年份两种同层状态；这是建议方案，尚未替换当前应用弹层。
