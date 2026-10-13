import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/about/about_page.dart';
import 'package:kazumi/pages/about/product_information_page.dart';
import 'package:kazumi/pages/about/credits_page.dart';
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
        child: (_, _) =>
            const ProductInformationPage(information: ProductInformation.legal),
      )
      ..route('/credits', child: (context, state) => const CreditsPage());
  },
);
