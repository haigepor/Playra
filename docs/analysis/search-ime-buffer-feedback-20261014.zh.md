# 搜索输入与拖动缓冲反馈

基线 `1bc1e847`，本轮按两个 M 级修复推进。范围为 ContentSearchScreen 输入属性、PlayerItem 的共享加载层、新增 PlayerBufferingOverlay、对应两份测试与本记录。不改解析接口、播放器依赖、缓存容量、进度拖动或续播逻辑。原有分析文档、dirty fastlane 子模块和其他未跟踪文件保留。

## 搜索安全键盘

当前框未设置 obscureText，但设置了 enableSuggestions=false。固定 Flutter 3.47.6 的 Android TextInputPlugin 在非 obscureText 且禁用建议时，会设置 TYPE_TEXT_FLAG_NO_SUGGESTIONS 和 TYPE_TEXT_VARIATION_VISIBLE_PASSWORD。模拟器实际 EditorInfo inputType=0x80091，其中 variation=0x90 是 visible-password。这证明应用确实提交了密码类型标记；小米安全键盘的具体呈现仍需真机复测。

改为明确 TextInputType.text、enableSuggestions=true，保留 autocorrect=false、Search action 和原有稳定 controller/focus/composing 处理。不是关闭小米系统的安全键盘设置，也不影响应用真正的密码框。

回归检查读取真实 TextInput.setClient 配置：修复前 enableSuggestions=false，检查失败；修复后通过。已有中文 ni/nihao→你好、光标编辑、清空及 tr 输入检查保持通过。

依据：[Flutter 3.47.6 Android TextInputPlugin](https://github.com/flutter/flutter/blob/3.47.6/engine/src/flutter/shell/platform/android/io/flutter/plugin/editing/TextInputPlugin.java#L267)。

## 拖动后的缓冲提示

共享 PlayerItem 原来仅按 isBuffering/video.loading 渲染转圈，没有消费 media_kit 的 bufferingPercentage。isBuffering 由每秒位置轮询更新，交互拖动期间该轮询取消，所以提示可能滞后。固定的 media-kit 已将 mpv cache-buffering-state 暴露为 state/stream.bufferingPercentage，无需修改 SDK、播放器或缓存策略。

将原转圈层提取为共享 PlayerBufferingOverlay，先在原行为上复现“原生缓冲事件到达却没有文字/百分比”的失败，再接入实时事件。动漫、影视的原生页面都使用 PlayerItem，内嵌与全屏共用该层。

- 直接订阅 buffering 与 bufferingPercentage，不等待每秒位置轮询。
- 显示真实“缓冲 N%”和对应圆形进度；缺失、NaN、越界数据保持“正在缓冲”的不定进度。
- 新一轮缓冲清掉旧进度；切换播放器重新绑定，取消旧订阅并用 generation 拦截迟到事件。
- 页面销毁取消订阅；覆盖层 IgnorePointer，继续允许拖动和点击控件。
- 百分比表示原生播放器当前起播缓冲目标的完成度，不代表整部视频已下载比例。浏览器后端没有该原生百分比时保持不定提示，不制造假百分比。

## 验证与回退

19 项定向测试通过：输入通道属性、中文 composing、缓冲实时更新、连续 seek 的旧百分比清理、换源/销毁、未知进度、既有原生影视适配和样式。579 项全量 Flutter 测试通过，五个改动 Dart 文件 analyze 无问题。编码与 diff 范围按最终交付复核。

新增受控限速视频和原生验证入口位于忽略的 .dart_tool，仅作验证，不进入交付 APK。小米专有键盘外观不以 AOSP 模拟器替代真机验收。

实际验证结果：

- emulator-5554 覆盖安装正式入口的 Release 包后，当前 EditorInfo inputType 两处均为 **0x1**，密码 variation 已清除；真实输入 tr 仍为 tr。
- 原生 media_kit/mpv 播放自建限速 MJPEG AVI。日志上报 buffering=true、percentage 0→5→20…→100、buffering=false；实际画面捕获“缓冲 20%”。播放中跳至未缓存的 45 秒，实际画面捕获“缓冲 25%”，不是按全片时长估算出的数字。
- 原生验证使用同一共享 HUD 和真实播放器事件；截图分别位于本机 .dart_tool/native-buffer-active.png、native-seek-buffer-active.png。临时服务器与 ADB reverse 已停止/移除，模拟器已恢复正常应用。
- 正式 APK 为 `build/releases/Playra-2.3.8-20308-43cee1c0-ime-buffer.apk`，2.3.8/20308，102610879 字节，SHA256 `40f17dad15d6422a341eef3a7bda12b76aeaf401ca4fe3d36bdfb68ff71b5d7c`。CRC、内置 SDK、ABI 与 v2 测试签名均通过；没有交付验证入口。
- Web 正式入口构建通过，9006 预览 JS hash 与本轮构建一致。Playwright 实测 input type=text，逐字 tr→tr你好、清空均通过，console error=0；中文 IME composing 另由组件测试覆盖。

修改清单：ContentSearchScreen 仅调整普通输入属性；PlayerItem 将旧加载层接入新增共享 HUD；两份测试覆盖输入通道及事件生命周期；本文记录证据和限制。未改变拖动目标、暂停/恢复顺序或缓存配置。代码修复提交为 `10f60e39`（搜索）和 `43cee1c0`（缓冲）；后续仅追加验证文档。

回退：revert 本轮搜索与缓冲两个修复提交；不恢复或删除此前用户文件，不改全局手机键盘设置。
