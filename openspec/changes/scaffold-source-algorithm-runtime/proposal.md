## Why

当前统一规则服务可以调用 HTTP API，但尚无 Python 算法服务与 Web/Android 的共同接入骨架。后续影视来源需要在独立适配器中实现签名和响应解密，避免向官方动漫规则核心添加平台脚本执行逻辑。

## What Changes

- 添加显式运行地址配置、受限 HTTP 客户端与规则请求装饰器；通过保留虚拟域名定位运行服务，不改变普通规则请求。
- 添加 Python 服务、受控适配器注册和模板；默认无影视资源或算法，提供健康、适配器、搜索、剧集与解析协议。
- Web 使用固定同源转发；Android 使用配置的服务地址，未配置时明确报错。支持开发模式地址而不放宽通用代理。
- 添加启动脚本、示例规则、契约检查与 Web/Android 编译证据。

## Capabilities

### New Capabilities
- `source-algorithm-runtime`: 跨平台外部算法运行服务骨架、可取消调用、固定转发及扩展协议。

### Modified Capabilities
无既有规范的破坏性修改。

## Impact

涉及来源 HTTP/Flutter 请求器、Web 后端和启动工具；新增 Python 标准库服务与示例配置。无新增 Flutter/npm 依赖，不嵌入 Python 到 APK，不接入真实影视来源，不改变首页或官方 16 条规则，不修改全局工具配置。
