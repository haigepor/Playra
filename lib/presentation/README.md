# 新旧页面的边界

`legacy/` 保存原版导航视图；旧的叶子页面仍在 `lib/pages/`，其路径保留以减少迁移影响。`modern/` 保存新版页面、布局组件和局部主题。`shared/` 只放两种界面共用的导航与版本选择，不放新版配色或卡片布局。

新增完整页面时，在 `modern/pages/` 编写 Widget，通过原有路由模块的 `InterfacePageHost(legacy: ..., modern: ...)` 接入。保留路由参数和路径，复用现有业务控制器或仓库；不要在新页面重新创建收藏、历史、下载数据库。

新增页面不应导入旧版页面 Widget。如果暂时未迁移某个功能，跳转至现有公共路由，并在迁移清单中明确记录。追番页当前导入 `CollectController` 是共享业务依赖，不是旧页面复用。

`TabShell` 必须放在导航外观的 `InterfacePageHost` 之外，保留选中标签和 RouterOutlet；两套导航只接收索引、选择回调和 outlet。样式切换时叶子页面销毁并重新创建，根业务对象继续存活。

新版仅对 Android 启用。完整架构、修改清单和验收证据见 `docs/android-ui-skeleton.md`。
