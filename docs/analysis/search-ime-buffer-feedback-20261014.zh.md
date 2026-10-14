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

新增受控限速视频和原生验证入口位于忽略的 .dart_tool，仅作验证，不进入交付 APK。模拟器输入类型及原生事件/画面证据追加在本节；小米专有键盘外观不以 AOSP 模拟器替代真机验收。

回退：revert 本轮搜索与缓冲两个修复提交；不恢复或删除此前用户文件，不改全局手机键盘设置。
