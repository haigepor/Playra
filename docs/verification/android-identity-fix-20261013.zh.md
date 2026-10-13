# Android 内置 SDK 首次身份创建兼容性修复

## 问题与定位

用户的红米 K50 / Android 15 在移动网络下加载电影失败，新诊断包显示 `IDENTITY_ERROR`（本地设备身份读取失败）。该错误包含本地身份创建与读取两种失败，并不表示远端电影接口返回了 HTTP 错误。

原创建逻辑先写临时 JSON，再调用 `os.link()` 发布到应用私有 `files/miomedia/device.json`。普通 Android 应用没有硬链接权限；[AOSP 应用安全策略](https://android.googlesource.com/platform/system/sepolicy/+/main/private/app_neverallows.te) 明确包含 `neverallow all_untrusted_apps file_type:file link`。缺陷位于接入适配层，SDK 的密码学算法没有问题证据。

本机模拟器 `adb shell getenforce` 实测为 `Permissive`（不强制安全策略），版本 Android 14 / x86_64。因此此前模拟器成功不足以验证正式设备的文件操作权限。未连接用户真机，尚未取得该手机的 SELinux 拒绝日志；本次证明的是与错误提示一致、且违反 Android 应用权限规则的创建缺陷，手机恢复状态需要覆盖安装后确认。

## 复现

在真实 `AndroidRuntime.request` 入口、临时新身份目录中，仅将 `os.link` 设为抛出 `PermissionError(EPERM)`：

```json
{"error":{"code":"IDENTITY_ERROR","message":"IDENTITY_ERROR"},"identityExists":false}
```

错误发生在会话初始化和业务网络请求之前。修改前新增测试记录了相同错误，随后修复。

## 修复行为

- 身份不存在时，以侧文件锁串行化不同实例的首次创建。Android/Linux 使用标准库 `fcntl`，Windows 使用标准库 `msvcrt`。
- 锁内复查现有身份，已经存在时原样复用。
- SDK 写入同目录临时文件后 `fsync`，再通过 `os.replace` 原子发布完整 JSON；不再调用硬链接。
- 等待锁遵守请求超时与取消；进程退出由系统释放锁。锁文件长期保留，避免并发实例锁住不同文件。
- 创建失败清理临时文件，允许普通重试。已有损坏身份保持原样报错，不自动删除、替换或重置。
- 不改变 SDK 算法、接入地址、会话校验、播放凭证策略、收藏、观看历史或播放进度。

## 验证

- 运行时 Python 全部测试：42 项通过。
- 覆盖禁止硬链接时首次请求、重启复用、八实例竞争只生成一份身份、发布失败无半写文件、锁超时后恢复、损坏身份不覆盖、桥接响应敏感字段过滤。
- 修复后使用同一真实 Android 桥接入口，在 `os.link` 持续抛出 `EPERM` 的条件下，用新身份请求实际电影目录成功：`hasVideos=true`、`identityExists=true`，约 1.22 秒。
- Release 构建成功，23.8 秒；ZIP 和嵌套 Python 包 CRC、三种 ABI、SDK 算法文件副本、16 份来源规则与装饰资产均通过校验。
- APK 的 Python 字节码确认包含锁与原子重命名，不含身份创建的硬链接调用；三种 ABI 均有 `fcntl` 标准库模块，适配层打包副本与源码字节一致。
- v2 签名验证通过，使用与上版相同的测试证书，可覆盖安装。
- 已覆盖安装到本机模拟器并实际打开电影页，电影推荐与七天热播榜正常；页面没有 `IDENTITY_ERROR`。现场截图在 `.dart_tool/android-identity-fix-20261013/emulator-movie.png`。
- 对比前后 APK 的 Python 字节码，排除编译时间戳头部后，仅 `miomedia_adapter.pyc` 有变化，其他 SDK 模块字节码相同。修改文件 UTF-8/语法检查通过，现有文件 BOM 状态保持不变。

## 日志中的其他问题

- `api.dandanplay.net` HTTP 403：弹幕服务拒绝请求，与电影 SDK 身份创建独立。弹幕客户端使用应用 ID 和签名；本次构建环境没有配置对应应用凭据，不能保证该服务可用。没有写入或公开凭据。
- `api.kazumi.fyi` HTTP 401：动漫镜像服务的鉴权失败。当前代码已有受保护请求在凭据缺失时切到官方接口、401/403 时回退的逻辑；仅凭这批日志不能确认手机包版本或回退最终结果。
- `api.bgm.tv`、`next.bgm.tv` 连接超时：动漫数据网络请求在 12 秒内未建立连接，不能由身份持久化修改解决。
- `cancel`：日志明确是请求被主动取消，常见于换源或离开页面，不等同于服务器失败。

本轮未修改这些独立来源的鉴权或网络配置。

## 交付与回退

修复包：`build/releases/Playra-2.3.8-identity-fix-20261013.apk`。

- 大小：104,046,323 字节。
- SHA-256：`2173087c29f6b7d505135273b4722edfed69947229fb40deebb0a9b5c4df7b57`。
- 修改：`tool/source_runtime/miomedia_adapter.py`（身份持久化）；`test_miomedia.py`、`test_android_bridge.py`（回归测试）；本报告。
- 源码回退位置：`.dart_tool/android-identity-fix-20261013/*.before`。此前诊断 APK 保留，没有覆盖。
- 真机验收：覆盖安装、保留应用数据，在同一移动网络下重试电影。若仍有 `IDENTITY_ERROR`，需要进一步区分已有文件损坏或私有目录读写失败，不应直接清除应用数据。
