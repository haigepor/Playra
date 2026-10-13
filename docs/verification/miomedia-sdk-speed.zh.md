# MioMedia SDK 加速版速度对照

日期：2026-10-12。结果：PASS。项目：`C:/Users/haige/Desktop/Playra`。

## 核心结果

同一份真实 `/video/modules` 首页响应（明文 448,045 字节），只替换 suite 函数绑定进行内存中对照，transport/ECSM 解析过程一致，不重复联网：

| 测量 | 旧 suite | 提供的加速版 suite | 提升 |
|---|---:|---:|---:|
| 真实响应完整解密，3 次中位数 | 19,646.957 ms | 286.993 ms | 68.46 倍 |

本次新版 SDK 实际内容请求总耗时 4,319.746 ms，其中联网 POST/响应读取为 3,847.968 ms。总耗时是一次真实样本，包含请求封装、网络、响应解密与 JSON 解析；不能把 68.46 倍解释为整个 APP 或网络速度提升。没有伪造旧版完整联网耗时。

## 六原语对照

同一进程、相同 447,726 字节确定性数据与固定测试密钥，3 次交替新旧测量取中位数；新实现预热一次，每次都校验完整明文相等。

| 原语 | 旧版解密 ms | 新版解密 ms | 倍数 |
|---|---:|---:|---:|
| M1 | 116.030 | 9.087 | 12.77 |
| M2 | 125.343 | 115.444 | 1.09 |
| M3 | 75,430.024 | 4.464 | 16,897.79 |
| M4 | 1,993.136 | 161.295 | 12.36 |
| M5 | 2,599.060 | 49.345 | 52.67 |
| M6 | 1,871.223 | 268.855 | 6.96 |

M3 这一行是整块大数据的原语压力对照；实际请求有不同算法链与 ECSM 分块，不能将这一极端倍数用于描述整个 SDK。主要结论应使用真实响应的 68.46 倍。

## 正确性与接入

- SDK suite/transport/playback 等完整自检 `SELFTEST ALL PASS`，playback 12/12。
- 新旧 suite 对 6 原语 × 8 数据长度（0、1、7、8、31、64、257、2049），加密密文与双向解密明文均一致，48/48。
- 同一真实响应每次完整明文逐字节相等。
- 加速实现原样复制自用户提供的 SDK；没有在项目内重写密码学实现，没有增加第三方依赖。
- 配置、签名、设备派生、播放凭证与身份文件保持原实现。
- 原始窗口、指标、密钥、设备身份、签名、响应密文均不写入基准报告。性能 JSON 只有公开测量结果。

## 复现

在项目根目录执行：

```powershell
python -u -X utf8 tool/source_runtime/miomedia_sdk_benchmark.py --old-suite .dart_tool/seven-day-ranking-before-20261012/tool/source_runtime/vendor/miomedia/suite.py --output .dart_tool/seven-day-ranking-before-20261012/sdk-speed.json
```

比较脚本：`tool/source_runtime/miomedia_sdk_benchmark.py`。旧版备份与原始测量 JSON：`.dart_tool/seven-day-ranking-before-20261012/`。结果受硬件、CPU 调度、响应体和算法链影响；本机结果不代表安卓设备或公网部署的固定延迟。
