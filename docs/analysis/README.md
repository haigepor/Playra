# 分析文档导航

本目录保存带日期和代码基线的研究、方案与实施记录。研究时的“尚未实现”、接口数量与测试结果属于当时快照，不能直接视为当前代码状态。

## 后续开发入口

- 新增 SDK、内容接口或规则：[统一接入规范](../development/source-sdk-onboarding.zh.md)与[接入验收模板](../development/templates/source-sdk-checklist.zh.md)。
- 平台打包：[构建流程](../release/build-platforms.zh.md)与[私有构建输入](../release/build-inputs.zh.md)。
- 主线整理、官方同步和分支恢复：[Git 工作流](../git-workflow.md)。

## 需求与设计历史

| 文档 | 当时关注的问题 | 当前阅读方式 |
|---|---|---|
| [接口规范化分析](source-interface-standardization-20261013.zh.md) | 规则、SDK、平台传输与业务模型的职责 | 架构研究背景；新接口按统一接入规范实施 |
| [四类内容与并发搜索方案](content-categories-search-plan-20261013.zh.md) | 动漫、影视、漫剧、剧集与搜索聚合 | 分类决策背景，结合实际搜索实现记录阅读 |
| [全页面样式审查](all-pages-style-audit-20261014.zh.md) | 主题 token、小屏、播放器与二级页面 | 问题快照，修复结果见下表 |
| [Mio 线路数量核对](miomedia-lines-audit-20261014.zh.md) | 样本中的线路种类和空目录 | 来源采样，不能当作全站固定线路白名单 |
| [SDK 分层与最高画质方案](sdk-provider-lines-quality-plan-20261014.zh.md) | SDK 播放源、动态线路、画质证据与扩展 | 已实施方案的设计依据，结果见实施记录 |

## 实施与核验记录

| 主题 | 记录 |
|---|---|
| 搜索、来源聚合与平台入口 | [搜索实施](../verification/content-search-implementation-20261013.zh.md) · [搜索后续优化](../verification/search-followup-20261013.zh.md) |
| 页面细节修复 | [样式修复](all-pages-style-fixes-20261014.zh.md) |
| SDK 统一播放与接入文档 | [SDK 实施记录](sdk-provider-lines-quality-implementation-20261014.zh.md) |
| 小米输入方式与原生缓冲反馈 | [输入与缓冲记录](search-ime-buffer-feedback-20261014.zh.md) |

2026-10-14 整理时补齐此前仅保存在工作区的五份研究文档，保留其原始日期、结论和限制；未把历史报告改写成新的接口实测结果。
