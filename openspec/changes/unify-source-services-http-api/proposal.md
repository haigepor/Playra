## Why

规则搜索、剧集、首页目录和播放解析分散在不同模块，页面直接依赖规则配置，HTTP 服务目前只有代理与浏览器解析。需要统一内容源契约，供新旧页面、Android、Windows、Web 和 HTTP 调用共享，同时保留旧规则 JSON 的兼容性。

## What Changes

- 建立稳定来源身份、能力、内容引用、分类、分页、线路、剧集、会话和分阶段健康状态模型。
- 通过统一服务复用 RuleEngine 的 XPath/API 搜索与剧集解析，迁移既有调用方。
- 首页目录改用来源适配器注册，不再由展示层识别规则名称。
- 统一播放解析与验证码上下文，保留平台实现和已验证 Cookie/User-Agent。
- 新增版本化 HTTP API、运行入口、结构化错误和接口文档；HTTP 与应用使用同一规则引擎。
- 保留旧 JSON、分享链接、规则管理和新旧页面行为；不修改现有首页视觉设计。

## Capabilities

### New Capabilities

- `unified-source-services`: 来源契约、兼容适配、目录、分类、分页、健康与跨平台解析会话。
- `source-http-api`: 版本化 HTTP 业务接口、规则读取、请求校验、隔离会话与共享规则执行。

### Modified Capabilities

无，仓库尚无现有 OpenSpec 能力规范。

## Impact

影响 lib/services/plugin、新增 lib/services/source、首页目录适配、搜索与播放调用方、tool 下 HTTP 服务及其文档和测试。纯 Dart 核心需要将 Flutter 网络/日志默认依赖放入条件运行时适配层；不另建 XPath/JSONPath 解析实现。HTTP 服务默认仅监听本机，使用现有 Node 后端执行浏览器解析/验证码，新增服务不会修改用户已经安装的规则。
