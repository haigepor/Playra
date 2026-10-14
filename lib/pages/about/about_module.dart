import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/about/about_page.dart';
import 'package:kazumi/pages/about/product_information_page.dart';
import 'package:kazumi/pages/my/my_controller.dart';

final aboutModule = createModule(
  path: '/about',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) =>
            AboutPage(onCheckUpdate: inject<MyController>().checkUpdate),
      )
      ..route(
        '/help',
        child: (_, _) =>
            const ProductInformationPage(information: ProductInformation.help),
      )
      ..route(
        '/privacy',
        child: (_, _) => const ProductInformationPage(
          information: ProductInformation.privacy,
        ),
      )
      ..route(
        '/legal',
        // 兼容旧深链，统一展示产品信息，不重新暴露已隐藏的外链页面。
        child: (_, _) =>
            AboutPage(onCheckUpdate: inject<MyController>().checkUpdate),
      )
      ..route(
        '/credits',
        child: (_, _) =>
            AboutPage(onCheckUpdate: inject<MyController>().checkUpdate),
      );
  },
);
