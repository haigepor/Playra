# Lumina 在 Flutter iOS 本地运行的可行性核验

核验日期：2026-10-16。依据 Playra 当前源码、实际 SDK 交付物与 Flutter/Dart/Apple 官方文档。本文是方案分析，不表示已移植协议、生成 iOS 引擎或通过真机验收。

**状态更新：用户已暂停iOS研究，当前实施为iOS隐藏Lumina、保留旧动漫来源。本文只保留历史核验，不作为当前接入方案或待执行承诺。**

## 结论

Flutter 可以承载“Dart 协议层 + 本地 C 引擎”，从而消除受控远端 Python 服务这一层；仍需请求内容接入点、外部解析器和媒体 CDN，不等于离线播放。**当前交付包尚不具备直接启用这一方案的输入**：缺少引擎 C 源码/头文件或 iOS 预编译产物，Windows 环境也没有 Xcode/iOS SDK。

建议先完成原生引擎的 iOS 最小验证，再决定协议移植。保留当前已实现的远端契约作为现有可交付方案；不在本轮分析中替换 Android 已接通的 Python 链路。未来本地方案是独立实现和验证项目，不是给现有 Python 包增加一个平台开关。

## 对提供方案的逐项核对

| 说法 | 实际证据 | 判断 |
|---|---|---|
| Playra 已有 iOS FFI 工程 | `third_party/ech_http/hook/build.dart`处理 OS.iOS、targetSdk 与 Apple 工具链，`native.dart`包含 @Native/assetId | 已有工程模式，但不是本轮 iOS 构建通过证明 |
| 现有 native assets 就是静态库 | build.dart 的 CodeAsset 使用 DynamicLoadingBundled；CMakeLists.txt 使用 add_library(... SHARED ...) | 当前先例是随包动态库，不能推导 `.a + @Native`自动完成静态链接 |
| 引擎是纯 libc C、源码零改动 | 对 SDK 全目录（含忽略文件）搜索仅找到设备桥 core_serve.c；未找到 lumafuse_engine_fuse.c、引擎头文件或 .a | 缺输入，无法核验 include、JIT、内存实现和零改动结论；设备桥不是自研引擎 |
| macOS arm64 库能直接用于 iOS | 随包 dylib 解压后 Mach-O64/arm64，LC_BUILD_VERSION platform=1（macOS），min13.0.0/SDK15.1.0 | 架构相同不等于平台相同，不能改名后用于 iOS |
| 只需要一个很小的 native 引擎 | fuse_image.bin.gz 压缩 3,719,655B，解压尺寸 87,642,260B，约83.6MiB | 压缩包小不代表磁盘/RSS/首次解压开销小；实际驻留内存尚未测量 |
| 协议约1000–1200行即可移植 | codec51/envelope129/rsaio183/auth88/aes_cbc158/play185/client206，共1000行；_fuse封装另有约470行，block485行 | 是粗略源码体量，不是交付工作量；不能把测试、异常、缓存、网络与生命周期排除后承诺工期 |
| Dart 自带全部所需密码实现 | BigInt.modPow 可表达 RSA 模幂；标准库没有现成通用 AES-CBC/RSA/DER/该协议信封实现 | 可按规格实现，但需要迁移和审查；“有 BigInt”不等于安全正确的 RSA 解包已经具备 |
| Dart FFI 天然零拷贝 | FFI 可访问原生内存，普通 Dart TypedData 不会自动成为生命周期安全的 C 缓冲区 | 必须明确分配/释放、长度、同步边界与所有权；按批次调用优先，不承诺零拷贝 |
| 无 JIT、随包静态库即可保证过审 | Apple 2.5.1/2.5.2涉及公用API、自包含与动态代码限制；5.2涉及第三方内容/服务权限 | 这是可设计满足的技术条件，不是上架保证 |

## 推荐的未来本地调用链

```text
Flutter 页面 / 当前 Lumina 内容和播放模型
  → Lumina 业务接口（channels/catalog/search/detail/play）
  → iOS 本地 Dart 协议实现
      ├─ HTTP、认证缓存、随机 nonce、信封/RSA/CB64、解析器处理
      └─ 长驻工作 isolate → C ABI → iOS 原生引擎 + 随包镜像
  → 短时效 media URL + headers
  → 当前 PreparedPlayback（准备与播放分离）
  → 用户点击 → 播放器
```

接口可以复用当前七个受限操作及统一公开模型，但传输实现应分为远端和本地，不让 UI 直接调用密码函数，也不强制本地实现伪装成 HTTP 服务。Windows/Linux/Web BFF继续使用现有 Python SDK；浏览器不能直接调用 dart:ffi。

引擎应保留单调用串行约束：当前 _fuse 注明 guest 堆/栈/寄存器为进程级共享。多个 isolate 仍处于同一进程，不会自动获得独立 C 全局状态；不能为追求并发删除锁。长计算放工作 isolate，页面取消负责网络取消和过期结果丢弃；原生调用是否可中断取决于引擎额外支持，不能虚报即时中断。

## 协议迁移不能省掉的行为

- 认证固定输入、90秒缓存、每请求随机 nonce、固定路径和参数原文，包括原始拼写路径。
- RSA-2048 DER/大端转换、PKCS#1填充及拒绝非法输入、CRT结果；仅有 BigInt.modPow 不是完整实现。
- CB64、紧凑 JSON/UTF-8、PKCS#7、请求和响应信封、明文端点分支。
- 引擎初始化、镜像完整性、认证专用管线、C(K)、标定、状态字节布局、解密与错误码。当前 C 快路径可以减少 Python F 的迁移，但不能把 EBlock 的编排全删掉。
- 解析器脚本中的参数提取与密文处理，保持为已限定的数据解析，不引入远端脚本执行。
- play 的真实 play_fmt/part、完整直链解析、UA空字符串和Referer；resolve=False仍请求凭证，不能当离线检查。
- 超时、取消、返回体限制、重定向/外链约束、稳定错误码、短时效刷新和持久设备身份。

原 SDK 继续保持算法字节不变，作为对拍基准；新增 Dart 实现不得回写供应商目录。固定随机输入/时间用于测试，运行时必须恢复安全随机数和真实时间。

## iOS 原生打包的两个可选实现

1. **随包 framework/code asset**：优先复用项目已经采用的 DynamicLoadingBundled 工程模式，在 Mac/Xcode 构建 iPhoneOS arm64 与所支持模拟器切片，按 Flutter 要求保持同一 assetId/库名并完成签名。
2. **静态链接引擎**：源码或 `.a` 由 Xcode/Swift Package/CocoaPods 等原生构建集成，保留需要的导出符号，再通过进程符号查找/LookupInProcess绑定。`@Native(assetId:)`只是声明绑定，不负责将任意 `.a` 自动链接进 Runner。

两者都可能成立；当前证据不足以预先宣称静态库更快。要实测 Release/AOT 的 dead stripping、符号可见性、arm64 设备与 arm64 模拟器的平台差异，以及资源随包读取。镜像若必须文件路径，可从只读 Bundle资源读或解压至私有 Application Support，校验摘要后复用；不得把原生代码下载到可写目录再加载。

## 应如何分阶段验证

| 阶段 | 通过条件 | 当前状态 |
|---|---|---|
| 输入齐备 | 引擎C/头/构建说明或可信iOS产物；固定向量/镜像摘要；Mac+Xcode | BLOCKED：当前包无源码/iOS产物，本机为Windows |
| 最小原生桥 | iOS设备和模拟器初始化、认证与多块加解密逐字节对拍；Release符号不丢失 | 未执行 |
| Dart协议 | SDK现有11项向量全部等价；补随机、畸形、边界长度、中文与特殊集名、错误分支 | 未执行 |
| 真连链路 | config/频道/列表/搜索/详情/凭证/解析器/CDN正确；无远端Python地址也能调用 | 未执行 |
| 产品行为 | 自动准备无media open；点击后首帧与进度；换集取消、过期刷新、手动锁线、旧历史收藏 | 未执行 |
| 性能 | 冷/热、样本数、p50/p95、首帧、RSS峰值、解压磁盘占用；前后台切换与弱网 | 未执行 |

不把 Python/桌面门禁通过、macOS Mach-O产物或 Android 播放结果当作 iOS 通过。现有 Windows环境可提前做 Dart/Python差分验证；iOS构建与设备验收必须在支持环境进行。

## 与现有约束的关系

- 本地协议运行必须拥有执行所需的固定协议材料；放进 iOS 二进制后不能再保证这些材料“永不出服务器”。可做到不写日志、不暴露给 Web/公开接口、妥善存储身份，但不能承诺客户端绝对不可提取。若要求密钥永不进入终端，则必须保留服务端方案。
- ARM32仍维持本轮约定：不登记Lumina、不新增模拟器或降级实现；未来iOS支持不能改变该边界。
- Android未来可评估共用Dart协议，但现有Chaquopy仍承载AniFive/MioMedia，迁移Lumina不会自动移除整个Python运行时或其体积。
- 随包解释器是另一条需要单独维护和审核的路径；当前没有必要为iOS额外引入CPython、PythonKit或Unicorn。

## 官方依据

### GitHub Actions能否替代本地Mac

可以。已通过GitHub连接器读取远端`haigepor/Playra`当前`.github/workflows/release.yaml`，存在`Playra platform build`手动入口，platform含ios；本地`tool/cloud_build.py`将ios映射到macos-15，工作流选择Xcode26.2。GitHub官方当前macos-15 arm64镜像清单仍列出`/Applications/Xcode_26.2.app`。本轮只核对配置与官方镜像，未触发云任务，不把可配置等同于本次构建已通过。

现有工作流能构建Flutter设备unsigned IPA，不能凭空生成缺失的引擎或移植Python协议。可分为两个独立产物阶段：

1. 交付方提供引擎C/头/构建说明时，由私有macOS工作流编译device arm64和所需模拟器切片，原生对拍通过后输出带摘要/ABI/最低系统版本的库或XCFramework。若交付方直接提供可信iOS产物，跳过编译、只做验证和集成。没有两者时明确失败，不上传伪产物。
2. Playra恢复私有原生产物与镜像，接入经向量验证的客户端协议执行层，再复用现有Flutter工作流构建、验证Mach-O平台/符号及打包。只交付加解密`.a`不能让Python的Client/play/envelope自动在Dart执行；应同时交付协议层/绑定，或另做与原SDK对拍的协议移植，不按规格从零重建缺失块引擎。

库编译和unsigned包通常不需要Apple分发证书；生成可安装真机/Ad Hoc/TestFlight产物需匹配的签名和描述文件，按[GitHub官方签名流程](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)在临时keychain导入，完成后清理。CI模拟器测试可证明加载与协议行为，不能代替真实iPhone性能/媒体解码验收。

私有引擎源码/SDK镜像应从受控输入恢复，验证SHA256，不把它们当公有release附件或打印配置到日志。现有公开工作流没有Lumina原生产物恢复步骤，不能直接宣称云端Lumina本地版已就绪；本轮没有修改工作流或触发发布。

官方依据：[GitHub macOS runner镜像](https://github.com/actions/runner-images)、[macos-15 arm64软件清单](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md)。

- [Flutter FFI与构建钩子](https://docs.flutter.dev/platform-integration/bind-native-code)：当前推荐package_ffi，code asset默认示例为随包动态库；iOS切片名称和平台集合须一致。
- [Flutter静态/动态链接与符号保留](https://docs.flutter.dev/platform-integration/legacy-ffi-plugin)：静态源码链接/进程符号读取可用，Release需处理符号剥离。
- [Dart Native绑定](https://api.dart.dev/dart-ffi/Native-class.html)：assetId与symbol负责解析；不能替代原生链接。
- [Dart BigInt.modPow](https://api.dart.dev/dart-core/BigInt/modPow.html)：提供模幂运算，未承诺整套RSA或恒定时间性质。
- [Flutter iOS开发环境](https://docs.flutter.dev/platform-integration/ios/setup)：Xcode、iOS SDK及模拟器/设备要求。
- [Apple审核指南](https://developer.apple.com/app-store/review/guidelines/#software-requirements)：代码加载、公用API及第三方服务/内容是不同审核维度，本文不作审核结果承诺。
