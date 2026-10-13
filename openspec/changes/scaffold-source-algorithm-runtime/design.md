## Context

L 级共享请求契约。已有 JSON API 规则、SourceService 和原生/Web 请求器；16 条动漫规则不修改。本轮按此前确认的 HTTP 适配方向和 OpenSpec 流程执行，范围是运行骨架。

## Goals / Non-Goals

**Goals:** Web/Android 可调用同一外部 Python 协议，支持健康、受控适配器、搜索、剧集、解析、错误与有限预算。证明运行请求经过实际 RuleEngine，普通规则仍委托原请求器。

**Non-Goals:** APK 嵌入 Python、任意脚本上传/执行、真实影视来源、通用影视资料页、既有集数调度问题或公网生产部署。

## Decisions

1. 使用虚拟地址 `https://source-runtime.playra.invalid/v1/...` 作为明确的规则接入标记。请求装饰器只拦截该主机的 HTTPS、已知路径/方法；其余全部委托。保留 RuleEngine 的 XPath/JSONPath 解析，避免再实现解析器。
2. Web 基址固定为当前 origin 的 `/api/runtime/v1/`；Node 只将白名单端点转发到管理员配置的本机 Python 端口，默认关闭。Android 使用 `PLAYRA_SOURCE_RUNTIME_URL`；默认为空，不自动请求或假装具备本机 Python。开发 HTTP 需显式开关。
3. Python 标准库服务提供维护者登记的适配器。默认模板 capabilities 为空，操作返回 UNSUPPORTED；测试 fixture 与模板隔离，示例规则不自动安装。
4. 服务采用有限在途操作、请求/响应大小、时间预算和合作式取消。HTTP 中断可取消客户端并让适配器上下文失效，但不承诺强杀任意 Python 线程。签名/解密后续写在适配器内，不进入 APK/规则导出。
5. 返回结构复用已有 API 规则 mapping：搜索 data/name/url，章节 data/roads/episodes，解析 data/url/headers/format/expiresAt。保留结构化错误，不把未配置/解密失败当空资源。
6. Python 使用明确的前台 CLI 启动；Web 启动脚本检查健康状态并显式传入 Python 端口，Android 沿用 dart-define 配置。本机服务只绑定 loopback；未来生产服务须另外选择成熟 HTTP 部署、HTTPS 和用户鉴权。

## Risks / Trade-offs

- [缺少真实影视协议] → 默认空能力模板；未来接入再确定算法和资料模型。
- [Windows 地址误用于 Android] → 文档区分 adb reverse、模拟器与正式 HTTPS，禁止默认 localhost。
- [脚本不配合取消] → 有限 worker 与预算，上下文要求检查取消；不把线程等同于沙箱。
- [跨平台回归] → RuleEngine 实际 fixture、原 API 集成回归、Node 固定转发检查与 Web/Android 编译分别验证。

## Migration Plan

仅主动导入示例运行规则时启用运行路径；普通规则不迁移。回退使用 `.dart_tool/runtime-skeleton-before-20261012/` 的本轮前备份，停用 Python 服务和 Web 开关，删除本轮新增文件，不撤回早前工作区变更。

## Open Questions

未来真实来源的算法、凭据、部署和影视资料契约待后续任务决定，不影响骨架完成。
