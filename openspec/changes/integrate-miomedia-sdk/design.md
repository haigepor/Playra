## Context
L 级跨运行契约接入。用户确认复用外部 Python SDK，先封装并整理接口。本次只完成 SDK 操作入口，不安装为完整播放规则。

## Goals / Non-Goals
**Goals:** SDK 可独立随服务运行；身份长期复用；握手严格检查；公开操作明确受限；真实联调与文档统计可复现。
**Non-Goals:** UI/影视通用资料模型、账号写操作、任意端点转发、客户端脚本执行、完整播放、远程多租户身份隔离。

## Decisions
1. SDK 原样复制到 vendor，算法模块与资源进行 SHA-256 对比，仅 profile/config 添加 TODO。保留零第三方运行依赖。
2. 身份位于忽略目录 `.dart_tool/miomedia/`，首次临时文件加原子独占发布，坏文件报错而非重建。每请求创建同身份客户端，避免修改并发请求共享 timeout；握手锁合并、短期复用校时状态。
3. HTTP 新增固定 `POST /v1/adapters/miomedia/sdk`，正文只含 operation/payload。操作限 recommend/banners/catalog/detail/episodes/qualities/exchange；握手内部处理，不公开密钥；未验证搜索与账户操作不开放。
4. 返回真实上游 data 与脱敏元数据；没有播放直链的 exchange 返回其真实客户端解析状态，不冒充 resolve 能力。登记为 sdk 能力，不默认安装为旧规则。
5. 只读操作最多一次网络重试，预算内检查取消。拒绝业务失败、错误密钥和错误协议；不重试业务拒绝或解密失败。SDK 本身的 socket timeout 不是强制任务终止，总预算仍由既有运行服务控制。
6. 端点清单从提供的全部接口文档去重统计，按文档说明与真实响应记录验证状态。无法确认的字段标记待验证，不猜测参数。

## Risks / Trade-offs
- [仅本地服务身份] → 当前 loopback 服务共用一个维护者身份；远程多设备接入需要后续会话隔离设计。
- [SDK 含默认环境值] → 本轮只作默认联调，不将密钥返回 Flutter、不提交发布；正式平台参数待替换。
- [API 文档与现场不同] → 记录 404、真实嵌套字段和客户端解析状态，能力列表不等于文档目录。

## Migration Plan
原来源不迁移。SDK 懒初始化，健康/清单不触发上游请求。回滚参考 `.dart_tool/miomedia-sdk-before-20261012/` 六个既有文件副本与基线哈希。

## Open Questions
正式平台配置、分类/搜索参数和客户端解析链待下一阶段确定。
