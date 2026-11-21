import 'package:kazumi/presentation/widgets/playra_page_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/detail/media_detail_page.dart';
import 'package:kazumi/pages/discover/browse_page.dart';
import 'package:kazumi/pages/discover/search_page.dart';
import 'package:kazumi/pages/playback_demo_page.dart';
import 'package:kazumi/pages/player/source_player_page.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/shell/shell_page.dart';

/// App routes. Content sources are registered in `features/sources/sources.dart`
/// and never listed here.
final appModule = createModule(
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const ShellPage(),
        transition: TransitionType.none,
      )
      ..route(
        '/browse',
        child: (context, state) {
          final args = state.arguments;
          if (args is BrowseArgs) return BrowsePage(args: args);
          return const _MissingArgumentsPage(label: '分类');
        },
        transition: TransitionType.material,
      )
      ..route(
        '/search',
        child: (context, state) => const SearchPage(),
        transition: TransitionType.material,
      )
      ..route(
        '/detail',
        child: (context, state) {
          final args = state.arguments;
          if (args is MediaKey) return MediaDetailPage(mediaKey: args);
          return const _MissingArgumentsPage(label: '详情');
        },
        transition: TransitionType.material,
      )
      ..route(
        '/play',
        child: (context, state) {
          final args = state.arguments;
          if (args is PlaybackRequest) return SourcePlayerPage(request: args);
          return const _MissingArgumentsPage(label: '播放');
        },
        transition: TransitionType.material,
      )
      ..route(
        '/player',
        child: (context, state) => const PlaybackDemoPage(),
        transition: TransitionType.material,
      );
  },
);

void navigateToPlayer(BuildContext context) {
  context.pushNamed('/player');
}

final appNavigatorKey = rootNavigatorKey;

class _MissingArgumentsPage extends StatelessWidget {
  const _MissingArgumentsPage({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(label)),
      body: SafeArea(
        child: PlayraPageState(
          icon: Icons.link_off_rounded,
          title: '无法打开此页面',
          action: FilledButton(
            onPressed: () => context.navigate('/'),
            child: const Text('回到发现'),
          ),
        ),
      ),
    );
  }
}
