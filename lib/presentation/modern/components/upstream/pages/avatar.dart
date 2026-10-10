import 'package:kazumi/presentation/modern/components/upstream/common/base_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class AvatarPage extends StatelessWidget {
  const AvatarPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BaseScaffold(
      appBarTitle: 'Avatar',
      children: [
        ShadAvatar(
          // 使用项目资源，让组件预览可以离线运行。
          'assets/images/logo/logo_android.png',
          placeholder: const Text('CN'),
        ),
      ],
    );
  }
}
