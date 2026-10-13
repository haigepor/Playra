# MioMedia SDK 第一阶段验证记录

日期：2026-10-12。范围：Python SDK 封装、固定 HTTP 操作、Web 桥接、Flutter 调用方法与接口清单。

## 结果

第一阶段 SDK 接入：PASS。页面数据绑定、搜索适配、客户端播放材料解析和 Android 实机验证不在本阶段完成范围内。

| 检查 | 结果 | 覆盖 |
| --- | --- | --- |
| 随包 SDK selftest.py | SELFTEST ALL PASS | SDK 自检向量 |
| Python unittest discover | 18 PASS | 会话、身份、并发、错误、重试、取消、HTTP 与实际 SDK 加密传输 |
| Node runtime/security tests | 8 PASS | 固定操作桥接与请求边界 |
| Flutter source_runtime/source_service/rule_engine tests | 34 PASS | SDK 调用封装与已有规则服务回归 |
| Dart analyze | No issues found | 调用方法、测试和集成工具 |
| Dart Web 编译 | PASS | SDK 调用方法及 Web 同源地址分支编译为 JavaScript |
| miomedia_runtime_integration.dart | 9 PASS | Dart → Python 及 Dart → Node → Python 的实际请求路径 |
| source_runtime_integration.dart | 21 PASS | 原有运行骨架与规则执行兼容 |
| SDK 源文件 SHA-256 比较 | 9 个文件完全一致 | 算法、传输、设备、签名、客户端、自检及二进制表 |
| 两个环境文件比较 | 仅 TODO 注释差异 | profile.py、config.py 的原配置值保留 |

## 默认环境的真实接口

`miomedia_live_check.py` 对 7 个内容操作分别检查 HTTP、解密与业务成功。握手在内部执行，严格验证本地派生密钥与服务端返回值一致；重新创建封装实例后复用同一设备身份。

| 操作 | 结果 | 本轮数据 |
| --- | --- | --- |
| recommend | PASS | 10 个推荐作品 |
| banners | PASS | 20 条轮播 |
| catalog | PASS | 默认请求 10 个作品及 pageinfo |
| detail | PASS | video 资料及真实 player 线路 |
| episodes | PASS | 检查作品的一条线路返回 288 集 |
| qualities | PASS | 清晰度与临时兑换令牌 |
| exchange | PASS | 返回客户端解析材料，playUrl 为空 |

记录位于忽略目录 `.dart_tool/miomedia/live-check.json`，只保存状态、耗时、字段名与数量。设备身份文件需要持续保留，不作为公共验证材料。

7 个公开内容操作与内部握手共覆盖 8 个上游路径。文档整理为 132 个明确端点，其中 130 POST、2 GET；其余接口没有因列入清单而被认定为可用。

## 范围与限制

- 对本轮前 1027 个文件的哈希比较，只有接入说明列出的 6 个既有文件发生变化；其他修改均为本阶段新增文件。
- 原有 16 条动漫规则、页面和平台配置保持原样。
- 本轮新增及修改的文本通过严格 UTF-8 检查；无 BOM 或替换字符。新增代码和文档通过中性用词检查。
- SDK 未引入第三方 Python 运行依赖，也未执行返回的 Lua 材料。
- Web 验证覆盖真实同源桥接路径；本轮没有打开浏览器验证新页面。Android 沿用运行服务地址配置，本轮没有打包或实机安装。
- 正式环境绑定值待平台确认；本地服务目前使用一个持久设备身份，远程多用户部署需增加鉴权和身份隔离。
- 分页参数的实际语义、分类和搜索参数仍待验证。播放需要补齐客户端解析契约或获得直接播放 URL。
- 备份位于 `.dart_tool/miomedia-sdk-before-20261012/`。回滚只恢复本轮差异，保留已有工作区与必要的设备身份文件。
