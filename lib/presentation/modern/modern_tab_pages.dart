import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/collect/collect_controller.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'pages/calendar_page.dart';
import 'pages/discover_page.dart';
import 'pages/library_page.dart';
import 'pages/profile_page.dart';

// 仅移动端主导航复用现有页面；收藏、历史、同步仍使用根模块的共享对象。
const modernTabPageBuilders = <WidgetBuilder>[
  _discover,
  _calendar,
  _library,
  _profile,
];

Widget _discover(BuildContext context) => const ModernDiscoverPage();
Widget _calendar(BuildContext context) => const ModernCalendarPage();
Widget _library(BuildContext context) =>
    ModernLibraryPage(controller: inject<CollectController>());
Widget _profile(BuildContext context) =>
    ModernProfilePage(controller: inject<MyController>());
