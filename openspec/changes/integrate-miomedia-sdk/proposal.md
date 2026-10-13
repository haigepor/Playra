## Why
运行骨架已就绪，MioMedia SDK 已通过基础接口联调。先完成可独立运行的 SDK 封装，让 Web/Android 通过既有 HTTP 契约调用，并明确文档接口与实际可用能力。

## What Changes
- 随服务携带纯标准库 SDK，算法文件逐字节保留，仅环境文件添加待替换说明。
- 新增稳定本地服务身份、严格握手、并发会话复用、有限网络重试和错误映射。
- 新增受限的 MioMedia SDK HTTP 调用入口与跨平台客户端方法。
- 整理完整文档端点清单、数据说明与真实接口检查记录。

## Capabilities
### New Capabilities
- `miomedia-sdk-adapter`: 外部 Python SDK 封装、明确允许的内容操作及运行桥接。
### Modified Capabilities
无。本次新增专用入口，不改变普通规则行为。

## Impact
修改运行骨架的 Python 登记/路由、Node 白名单与 Flutter 客户端；新增 SDK、封装、测试与文档。不修改 UI、16 条动漫规则、SDK 算法或既有业务数据。设备作用域为本地服务实例，尚非远程多设备会话系统。
