# 七天热播榜、选集三档卡片与 SDK 加速验收

日期：2026-10-12。实现结果：PASS。项目：`C:/Users/haige/Desktop/Playra`。

## 已完成的行为

- Python 新增只读受限操作 `hotRank`，对应已核验 `/video/modules`；必填 categoryId 字符串、pageIndex 正整数、pageSize 正整数。页面固定 pageIndex=1、pageSize=20。
- 只投影 MOD_818368 与其原数组前十；保留 name/k/boardTabs、字符串作品 ID 与原始顺序。窗口和指标明确为 null。没有按累计播放量、评分、weight、sortOrder 或题材重排、去重和过滤。
- 推荐与热门使用 0；影视使用真实分类资料 ID，动漫子分类使用已核验绑定/实际资料。不借用首页榜单填充没有对应分类的入口。动漫“全部”没有来源聚合分类 ID 时显示空状态。
- 每个 categoryId 拥有独立缓存、取消令牌、加载与错误状态。慢榜单不会阻塞目录；失败可重试，刷新失败保留旧榜；首次采用骨架屏。
- 榜单卡片显示原始位次，并通过既有 MioMedia 详情回调打开，不转成 Bangumi 身份。
- 选集使用共享三档测量：短名称（至多八字并能放入小格）紧凑多列；中等名称两列；超过半行文本容量的名称全宽、最多两行。计算包含实际字体、文字缩放、间距与播放标记，不因选中而跳动。
- 分段标签使用 240ms 滑块；降低动画设置下瞬时切换。升降序与分段只改变展示，播放仍使用真实 episodeNum/code。
- 原样同步提供的 suite.py、transport.py、__init__.py；其他 SDK 文件（含 profile/config、签名、设备、playback、块实现和表）与任务开始时哈希一致。持久身份文件不变，无新第三方依赖。

## 验证证据

| 检查 | 结果 |
|---|---|
| 提供的 SDK selftest.py | SELFTEST ALL PASS |
| 内置 SDK 直接/模块两种自检 | SELFTEST ALL PASS，playback 12/12 |
| 提供的 hot_rank_probe.py | 首页/动漫电影均为 MOD_818368、七天热播榜、hot、热播榜、10 项 |
| 真实 SDK 与 HTTP 桥接对照 | 两份榜单与 probe 顺序一致，连续两次顺序相同，分类不同 |
| 身份文件前后对照 | unchanged=true；报告不记录身份或密钥内容 |
| 新旧 suite 固定数据对照 | 6 原语 × 8 长度，加密/解密一致，48/48 |
| Python source_runtime 全部测试 | 30 PASS |
| Flutter 五个聚焦测试文件 | 23 PASS |
| Dart 静态分析 | 变更代码无错误/警告；首页两条既有字符串插值 info 保留 |
| 最终 Flutter Web 构建 | PASS，main_home_preview.dart |
| OpenSpec strict 验证 | PASS |
| UTF-8 / diff / 范围 | 严格 UTF-8、无 BOM/替换字符，代码修改限本次 scope |

真实桥接前十响应：全站 13,555 字节，动漫电影 13,282 字节，减少约 450KB 的栏目数据向客户端转发。上游仍完整请求并由 SDK 解密，不伪装成平台只返回了 13KB。

真实榜单来源：全站首三项《仙逆》《女友的朋友》《凡人修仙传》；动漫电影首三项《进击的巨人 最终季 完结篇 后篇》《海贼王：红》《铃芽户缔》。电影首三项《唐探1900》《毒液：最后一舞》《一路向西》；综艺首三项《现在就出发第三季》《喜人奇妙夜2》《哈哈哈哈哈第六季》。这只是本次快照，不写入应用作为固定榜单。

## 浏览器实际页面

最终预览：`http://127.0.0.1:8940/?ranking=20261012-three-cards#/tab/popular/`。对应新版 Python 服务：`http://127.0.0.1:8949/v1/`，复用 `.dart_tool/miomedia/device.json`。

- 390×844：全站榜单、综艺榜单可见；打开真实《哈哈哈哈哈第六季》79 集详情，页面内和弹层日期类名称每行两项，宽约 175dp、高 56dp。
- 320×700：半行卡片宽 140dp；较长特辑标题自适应为全宽 288dp、64dp 高；日期名称不再挤在四个小格里。
- 弹层 1–50 / 51–79 可切换，真实日期集名随段变化。单元测试验证动画中间帧与倒序后的非连续真实播放编号。
- 动漫电影真实榜首与全站不同；页面保留原 Bangumi 推荐栏目与来源榜单各自身份。
- 浏览器控制台只有现有外部封面 403/404；未发现 Flutter 溢出、异常或榜单 API 错误。首页旧 suite 触发 20 秒中止的问题已随提供的加速版消失。

截图与原始测量保存在 `.dart_tool/seven-day-ranking-before-20261012/`：home-rank-final.png、inline-three-cards-final.png、sheet-three-cards-final.png、sheet-320-mixed-final.png、live-ranking-fast.json、sdk-speed.json。

## 速度

同一真实响应的完整解密中位数从 19,646.957ms 降到 286.993ms，68.46 倍；逐字节结果一致。新版本次完整内容请求 4,319.746ms，其中联网 3,847.968ms。详细六原语、方法和复现命令见 `docs/verification/miomedia-sdk-speed.zh.md`。

## 修改文件、影响与回滚

| 文件 | 用途与影响 |
|---|---|
| tool/source_runtime/miomedia_adapter.py | 新操作、严格参数、目标栏目前十投影；旧操作兼容 |
| tool/source_runtime/vendor/miomedia/suite.py | 原样提供的标准库加速实现 |
| tool/source_runtime/vendor/miomedia/transport.py、__init__.py | 原样提供的 ECSM 支持与公开导出 |
| tool/source_runtime/vendor/sdk-manifest.json | 记录内置 SDK 版本与文件哈希 |
| lib/services/source/miomedia/miomedia_service.dart | 保真榜单模型与固定请求 |
| lib/presentation/modern/miomedia/miomedia_home_controller.dart | 分类独立状态、缓存与取消 |
| lib/presentation/modern/miomedia/miomedia_rank_view.dart | 骨架/错误/空状态/有位次的竖卡 |
| lib/presentation/modern/miomedia/miomedia_browse.dart | 复用海报卡片，新增可选位次参数 |
| lib/presentation/modern/miomedia/miomedia_category_view.dart | 分类页接入真实榜单 |
| lib/presentation/modern/home/modern_home_view.dart | 首页/动漫榜单与当前榜单刷新 |
| lib/presentation/modern/miomedia/miomedia_detail_page.dart | 三档卡片、共享文字测量、滑块分段 |
| test/miomedia_rank_test.dart、miomedia_player_style_test.dart、miomedia_category_test.dart | 请求/保序/分类/取消/卡片/动画/分页回归 |
| tool/source_runtime/test_hot_rank.py | 桥接参数、投影、缺失与错误回归 |
| tool/source_runtime/miomedia_rank_check.py | 真接口/HTTP 顺序与重复调用对照 |
| tool/source_runtime/miomedia_sdk_benchmark.py | 同一数据与响应的速度比较，不输出密钥 |
| openspec/changes/integrate-seven-day-ranking/ | 提案、设计、两个能力规范与验收任务 |
| 本文、miomedia-sdk-speed.zh.md | 交付证据与复现说明 |

回滚位置：`.dart_tool/seven-day-ranking-before-20261012/`。只恢复该目录中对应旧文件，移除本次新文件并重建 Web；无需改身份文件，不覆盖本任务前的其他改动。当前仓库原有大量未提交修改，本次没有整体恢复、提交或归档其他 OpenSpec change。

## 剩余边界

- 安卓真机视觉/打包尚未复测；Flutter 与 HTTP 逻辑共用。
- 已有旧 Python 进程不会自动热加载。Web 本次用 8940 → 8949；安卓/部署应启动最新服务或连接新服务，保留原身份文件。没有终止原 8945 服务。
- 真实网络与硬件决定整体延迟；本机 68.46 倍是解密对照，不是整个应用固定加速倍数。
- 服务没有映射或没有 MOD_818368 时保留空状态；统计窗口与指标保持 null。
