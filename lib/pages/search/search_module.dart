import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/search/image_search_page.dart';
import 'package:kazumi/pages/search/search_controller.dart';
import 'package:kazumi/pages/search/search_page.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';

Widget _searchPage(BuildContext context, {String inputTag = ''}) =>
    InterfacePageHost(
      legacy: (_) => SearchPage(
        controller: context.read<SearchPageController>(),
        inputTag: inputTag,
      ),
      modern: (_) => ModernSecondaryScope(
        child: SearchPage(
          controller: context.read<SearchPageController>(),
          inputTag: inputTag,
          modern: true,
        ),
      ),
    );

void _provideSearchController(Scoped scoped) {
  scoped.add<SearchPageController>(SearchPageController.new);
}

final searchModule = createModule(
  path: '/search',
  register: (c) {
    c
      ..route(
        '/',
        provide: _provideSearchController,
        child: (context, state) => _searchPage(context),
      )
      ..route(
        '/image',
        provide: _provideSearchController,
        child: (context, state) => InterfacePageHost(
          legacy: (_) =>
              ImageSearchPage(controller: context.read<SearchPageController>()),
          modern: (_) => ModernSecondaryScope(
            child: ImageSearchPage(
              controller: context.read<SearchPageController>(),
              modern: true,
            ),
          ),
        ),
      )
      ..route(
        '/:tag',
        provide: _provideSearchController,
        child: (context, state) =>
            _searchPage(context, inputTag: state['tag'] ?? ''),
      );
  },
);
