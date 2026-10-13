## ADDED Requirements

### Requirement: Independent Android SDK
未配置外部运行地址的 Android 应用 SHALL 在应用内执行已接入 SDK，APK SHALL 包含 Python 运行时和 SDK，不依赖电脑进程或局域网地址。

#### Scenario: First content request
- **WHEN** 新设备安装 APK 并打开影视内容
- **THEN** 懒启动应用内 Python，经固定通道获取同一 JSON 业务数据结构

### Requirement: Platform compatibility
系统 SHALL 保留 Web 同源调用、显式外部 HTTP 配置和 Windows 未配置失败语义；SDK 算法 SHALL 保持字节原样。

#### Scenario: Explicit external URL
- **WHEN** 构建提供外部 RuntimeUrl
- **THEN** 调用既有 HTTP 服务，不同时启动一套嵌入客户端

### Requirement: Private persistent identity
SDK SHALL 仅在应用私有目录首次生成身份并持久复用；SHALL 不打包电脑身份文件或将密钥/身份返回界面。

#### Scenario: Restart and activity recreation
- **WHEN** 应用重启或 Activity 重建
- **THEN** 复用原身份，不清除观看数据，不主动执行身份替换

### Requirement: Bounded native bridge
原生桥接 SHALL 后台执行，仅接受固定操作、32 KB 请求与 2 MB 响应，支持取消和最多 60 秒预算；SHALL 拒绝任意脚本执行。

#### Scenario: Cancelled or malformed request
- **WHEN** 调用取消或携带未知操作/非法字段
- **THEN** 返回安全错误码，迟到响应不被应用采用，不公开内部堆栈

### Requirement: Verified test APK
交付 SHALL 核对 APK 的包名、签名、三种 ABI、SDK 与 Python 运行时，并分别记录编译、桥接测试和设备运行结果。

#### Scenario: Installation blocked
- **WHEN** 当前设备安装失败
- **THEN** 保留精确错误，不宣称真机播放已通过，仍提供已验证内容和签名的 APK
