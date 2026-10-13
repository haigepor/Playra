## 1. 平台编排
- [x] 1.1 添加纯标准库 Android Python 桥接、固定路由与私有身份目录
- [x] 1.2 添加后台 Kotlin 平台通道、懒启动和取消/有界队列
- [x] 1.3 接入 Flutter 原生默认调用，保留外部 HTTP/Web 兼容

## 2. 打包与验证
- [x] 2.1 接入 Chaquopy 17 / Python 3.11 与三 ABI 构建
- [x] 2.2 完成桥接、取消、错误、大小和身份复用测试，原 SDK 自检与回归
- [x] 2.3 构建 release APK，核验包名、签名、Python/SDK/规则/新版内容
- [ ] 2.4 尝试可用设备验证，记录真实结果、交付 APK 和回滚说明

2.4 状态：BLOCKED（真机运行）。APK、签名和回滚文档已交付；当前只连接此前安装隔离包报 restorecon 错误的模拟器，未连接用户目标真机。Windows Python 桥接真实联调不等价于 Android 执行。
