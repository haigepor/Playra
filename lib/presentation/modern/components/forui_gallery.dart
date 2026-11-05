import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;
import 'package:kazumi/bean/appbar/sys_app_bar.dart';
import 'package:kazumi/bean/dialog/dialog.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/widgets/playra_sheet.dart';

/// Uses the same components as product pages, so this route also verifies integration.
class ForuiGallery extends StatefulWidget {
  const ForuiGallery({super.key, this.onExit});
  final VoidCallback? onExit;
  @override
  State<ForuiGallery> createState() => _ForuiGalleryState();
}

class _ForuiGalleryState extends State<ForuiGallery> {
  bool enabled = true;
  bool checked = false;
  double progress = .4;
  int choice = 0;
  @override
  Widget build(BuildContext context) => ModernSettingsScope(
    child: Scaffold(
      appBar: SysAppBar(
        title: const Text('Forui 组件实验室'),
        leading: PlayraIconButton(
          tooltip: '返回',
          onPressed: widget.onExit,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: ListView(
        padding: PlayraLayout.pagePadding(context),
        children: [
          const Text('页面共用的组件、颜色与尺寸'),
          const SizedBox(height: PlayraSpace.lg),
          PlayraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('按钮'),
                const SizedBox(height: PlayraSpace.md),
                Wrap(
                  spacing: PlayraSpace.sm,
                  runSpacing: PlayraSpace.sm,
                  children: [
                    PlayraButton(
                      onPressed: () => KazumiDialog.showToast(
                        context: context,
                        message: '操作完成',
                      ),
                      child: const Text('主要操作'),
                    ),
                    PlayraButton.outline(
                      onPressed: () {},
                      child: const Text('次要操作'),
                    ),
                    const PlayraButton(onPressed: null, child: Text('不可用')),
                  ],
                ),
                const SizedBox(height: PlayraSpace.lg),
                const PlayraTextField(
                  decoration: InputDecoration(
                    labelText: '输入框',
                    hintText: '输入内容',
                  ),
                ),
                const SizedBox(height: PlayraSpace.lg),
                PlayraSwitchTile(
                  title: const Text('开关'),
                  value: enabled,
                  onChanged: (value) => setState(() => enabled = value),
                ),
                PlayraCheckboxTile(
                  title: const Text('复选框'),
                  value: checked,
                  onChanged: (value) =>
                      setState(() => checked = value ?? false),
                ),
                PlayraSlider(
                  value: progress,
                  onChanged: (value) => setState(() => progress = value),
                ),
                PlayraProgress(value: progress),
              ],
            ),
          ),
          const SizedBox(height: PlayraSpace.lg),
          PlayraCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: PlayraSpace.sm,
                  runSpacing: PlayraSpace.sm,
                  children: [
                    for (var index = 0; index < 3; index++)
                      PlayraChoice(
                        label: Text(['全部', '进行中', '已完成'][index]),
                        selected: choice == index,
                        onSelected: (_) => setState(() => choice = index),
                      ),
                  ],
                ),
                const SizedBox(height: PlayraSpace.md),
                const Wrap(
                  spacing: PlayraSpace.sm,
                  runSpacing: PlayraSpace.sm,
                  children: [
                    PlayraBadge(child: Text('在看 12')),
                    PlayraBadge.secondary(child: Text('更新至 24 话')),
                    PlayraBadge.outline(child: Text('1080P')),
                    PlayraBadge.destructive(child: Text('已完结')),
                  ],
                ),
                const SizedBox(height: PlayraSpace.md),
                const PlayraAlert(
                  title: Text('全站 Forui 组件重构'),
                  subtitle: Text('所有卡片、表单、弹窗均由统一 Token 驱动。'),
                ),
                const SizedBox(height: PlayraSpace.md),
                const PlayraDivider(),
                const PlayraExpansionTile(
                  title: Text('展开说明'),
                  children: [Text('圆角、间距、文字、交互状态统一来自应用主题。')],
                ),
                PlayraButton.outline(
                  onPressed: () => KazumiDialog.show<void>(
                    context: context,
                    builder: (dialogContext) => PlayraDialog(
                      title: const Text('确认操作'),
                      content: const Text('Forui 弹窗共用页面主题。'),
                      actions: [
                        PlayraButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('完成'),
                        ),
                      ],
                    ),
                  ),
                  child: const Text('打开弹窗'),
                ),
                const SizedBox(height: PlayraSpace.sm),
                PlayraButton.outline(
                  onPressed: () => showPlayraSheet<void>(
                    context: context,
                    title: '操作面板',
                    builder: (sheetContext) => Padding(
                      padding: const EdgeInsets.all(PlayraSpace.lg),
                      child: f.FTile(
                        title: const Text('返回页面'),
                        onPress: () => Navigator.pop(sheetContext),
                      ),
                    ),
                  ),
                  child: const Text('打开面板'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
