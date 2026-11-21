import 'package:flutter/material.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// 页面可见性观察器。新页面需要感知“被覆盖/重新显示”时复用它。
final rootRouteObserver = RouteObserver<PageRoute<void>>();
