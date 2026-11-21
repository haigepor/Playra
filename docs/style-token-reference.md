# Playra Token 速查表

> 来源：[playra_tokens.dart](../lib/presentation/theme/playra_tokens.dart)（2026-11-16 当前工作区）
> 用途：设计/开发对齐用的 token 字典；审计结论见 [style-token-audit.zh.md](style-token-audit.zh.md)。

## 1. 间距 `PlayraSpace`

| Token | 值 | 备注 |
| --- | ---: | --- |
| `tiny` | 2 | 微型间隙 |
| `xs` | 4 | 图标与文字 |
| `compact` | 6 | 非 4pt 网格值 |
| `sm` | 8 | 标准小间距 |
| `md` | 12 | 标准中间距 |
| `lg` | 16 | 页面/卡片内边距 |
| `xl` | 20 | 页面左右边距（实际页面固定使用） |
| `xxl` | 24 | 大区块间距 |
| `section` | 32 | **当前 0 引用**（Section 实际用 24） |

## 2. 圆角 `PlayraRadius`

| Token | 值 | 典型用途 |
| --- | ---: | --- |
| `thumbnail` | 8 | 小缩略图 |
| `control` | 12 | 输入框/按钮 |
| `poster` | 12 | 海报卡 |
| `card` | 16 | 卡片/对话框 |
| `hero` | 20 | Banner/Hero |
| `overlay` | 20 | 浮层 |
| `brand` | 24 | 品牌大圆角/HUD |

> 注意：`PlayraTokens` 里还有一套 `radiusXs=4 / radiusSm=8 / radiusMd=12 / radiusLg=16 / radiusXl=20`，与上表重叠但命名不同，属于重复尺度。

## 3. 字号 `PlayraType`

| Token | 值 | 典型用途 |
| --- | ---: | --- |
| `pageTitle` | 22 | 页面主标题（发现页） |
| `title` | 20 | 详情标题 |
| `section` | 18 | Section 标题 |
| `item` | 16 | Banner 标题/列表主文案 |
| `body` | 14 | 正文、按钮大号 |
| `label` | 13 | 海报标题、Chip |
| `caption` | 12 | 副标题、时间 |
| `small` | 11 | 元信息 |
| `micro` | 10 | 徽标 |
| `bodyHeight` | 1.5 | 正文行高 |
| `readingHeight` | 1.8 | 长简介行高 |

## 4. 布局 `PlayraLayout`

| Token | 值 | 当前引用 |
| --- | ---: | --- |
| `compactWidth` | 600 | 0（旧 `LayoutBreakpoint` 里还有一份） |
| `expandedWidth` | 840 | 1（仅 SnackBar 宽度判断） |
| `touchTarget` | 48 | 3 |
| `compactControl` | 40 | 0 |
| `inputHeight` | 48 | 2 |
| `listRow` | 56 | 0 |
| `toolbar` | 56 | 1（Forui TabBar） |
| `compactToolbar` | 52 | 0 |
| `icon` | 20 | 2 |
| `compactIcon` | 18 | 1 |
| `actionSheetWidth` | 520 | 2 |
| `sheetWidth` | 640 | 1 |
| `formWidth` | 760 | 0 |
| `readingWidth` | 880 | 0 |
| `catalogWidth` | 1120 | 0 |

## 5. 动效 `PlayraMotion`

| Token | 值 |
| --- | --- |
| `press` | 120ms（0 引用） |
| `state` | 200ms |
| `dialogEnter` | 220ms |
| `dialogExit` | 180ms |
| `sheetEnter` | 250ms |
| `sheetExit` | 200ms |
| `curve` | `Curves.easeOutCubic` |
| `reverseCurve` | `Curves.easeInCubic` |

## 6. 核心颜色 `PlayraTokens`

### 6.1 浅色

| Token | Hex | 说明 |
| --- | --- | --- |
| `background` | `#F7F8FC` | 页面背景 |
| `foreground` | `#22293C` | 主文字 |
| `surface` | `#FFFFFF` | 卡片/输入框表面 |
| `surfaceRaised` | `#F0F3FA` | 抬升表面 |
| `surfaceOverlay` | `#E8ECF6` | 浮层表面 |
| `muted` | `#E9EDFB` | 弱化背景 |
| `mutedForeground` | `#647087` | 次级文字 |
| `foregroundSubtle` | `#939EB5` | 弱化文字（**2.54:1，风险**） |
| `primary` | `#5267D9` | 主色 |
| `primaryForeground` | `#FFFFFF` | 主色上的文字 |
| `primaryContainer` | `#E0E6FF` | 主色容器 |
| `border` | `#E3E7F0` | 边框 |
| `borderSubtle` | `#EDF0F7` | 弱边框 |
| `destructive` | `#DC2626` | 危险 |
| `destructiveContainer` | `#FEE2E2` | 危险容器 |

### 6.2 深色

| Token | Hex | 说明 |
| --- | --- | --- |
| `background` | `#11141C` | 页面背景 |
| `foreground` | `#EDF0F8` | 主文字 |
| `surface` | `#1B202C` | 卡片/输入框表面 |
| `surfaceRaised` | `#222838` | 抬升表面 |
| `surfaceOverlay` | `#283042` | 浮层表面 |
| `muted` | `#202638` | 弱化背景 |
| `mutedForeground` | `#A5AFC5` | 次级文字 |
| `foregroundSubtle` | `#737F99` | 弱化文字 |
| `primary` | `#A7B7FF` | 主色 |
| `primaryForeground` | `#182142` | 主色上的文字 |
| `primaryContainer` | `#242C4C` | 主色容器 |
| `border` | `#30384A` | 边框 |
| `borderSubtle` | `#222A3A` | 弱边框 |
| `destructive` | `#F87171` | 危险 |
| `destructiveContainer` | `#381A1C` | 危险容器 |

### 6.3 状态色（`PlayraColors`）

| Token | 浅色 | 深色 | 当前使用 |
| --- | --- | --- | --- |
| `success` | `#16A34A` | `#4ADE80` | 0 |
| `successContainer` | `#DCFCE7` | `#152E22` | 0 |
| `warning` | `#D97706` | `#FBBF24` | 0 |
| `warningContainer` | `#FEF3C7` | `#362A12` | 0 |
| `destructive` | `#DC2626` | `#F87171` | 有 |
| `destructiveContainer` | `#FEE2E2` | `#381A1C` | 有 |
| `info` | `#2563EB` | `#60A5FA` | 0 |
| `infoContainer` | `#DBEAFE` | `#172A42` | 0 |
| `rankGold` | `#D97706` | `#FBBF24` | 评分 |
| `rankSilver` | `#64748B` | `#CBD5E1` | 0 |
| `rankBronze` | `#C2410C` | `#F97316` | 0 |
| `watching` | `#059669` | `#34D399` | 0 |
| `planToWatch` | `#4F46E5` | `#A7B7FF` | 0 |
| `watched` | `#64748B` | `#94A3B8` | 0 |
| `onHold` | `#D97706` | `#FBBF24` | 0 |
| `abandoned` | `#DC2626` | `#F87171` | 0 |
| `shimmerBase` | `#E2E8F0` | `#1E2433` | 0 |
| `shimmerHighlight` | `#F1F5F9` | `#2A3245` | 0 |

> 浅色状态值为 `PlayraTokens.light` 的覆盖值；深色状态值为 `PlayraColors` 的默认值。两者语义一致但部分色值不同，改色时容易漏改。
