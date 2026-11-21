# Playra 手机设计稿

先看[播放器横竖屏对照](player-preview.jpg)或[全套总览](overview.jpg)。每张 PNG 都可以单独打开评审，像素尺寸列在下表。

| 设计稿或素材 | 文件尺寸 |
| --- | --- |
| [发现](01-discover.png) | 887 × 1774 |
| [日历](02-calendar.png) | 887 × 1774 |
| [追番](03-favorites.png) | 887 × 1774 |
| [我的](04-profile.png) | 887 × 1774 |
| [搜索](05-search.png) | 887 × 1774 |
| [分类](06-browse.png) | 887 × 1774 |
| [竖屏播放与选集](07-detail.png) | 887 × 1774 |
| [横屏全屏播放](08-player.png) | 1846 × 852 |
| [横屏选集抽屉](08b-player-episodes.png) | 1846 × 852 |
| [播放演示](09-demo.png) | 1847 × 852 |
| [弹层与异常状态](11-states.png) | 1774 × 887 |
| [《夜航线》手机竖海报](art-night-route-poster.png) | 1086 × 1448 |
| [《夜航线》手机横幅／播放剧照](art-night-route-wide.png) | 1672 × 941 |

[设计报告](design.zh.md)整理了每页的现有功能、首屏和次级操作、异常状态、文案取舍、素材用途及官方参考资料。[完整提示词集](prompts.zh.md)保存了内置 ImageGen 的实际输入。竖屏播放改稿使用[用户给出的竖屏原稿](references/portrait-input.png)，横屏播放和选集抽屉共用[横屏参考稿](references/landscape-input.png)。

交付为手机端静态概念稿。第3集、08:42 和作品素材用于串联流程；两种方向的影视画面是分别生成的示例镜头。Flutter 中应保留同一视频实例并按实际播放事件填充数据。部分海报标题采用了画内题字，辅助状态拼图的页头还出现示意导航；开发时使用独立文字、真实四标签和启动失败专属界面。
