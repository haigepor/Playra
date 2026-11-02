import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/source_unavailable_page.dart';
import 'package:kazumi/presentation/modern/pages/content_search_screen.dart';
import 'package:kazumi/services/source/content_search.dart';

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => ContentSearchScreen(
          initialGroup: state.arguments is ContentGroup
              ? state.arguments as ContentGroup
              : null,
        ),
      )
      ..route(
        '/metadata',
        child: (_, _) => const SourceUnavailablePage(feature: '资料搜索'),
      )
      ..route(
        '/image',
        child: (_, _) => const SourceUnavailablePage(feature: '截图识别'),
      )
      ..route(
        '/:tag',
        child: (context, state) =>
            ContentSearchScreen(initialKeyword: state['tag'] ?? ''),
      );
  },
);
