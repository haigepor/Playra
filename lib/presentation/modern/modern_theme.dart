import 'package:flutter/material.dart';

/// 新版样式独立维护，继承用户的深浅色、动态取色和字体设置。
ThemeData modernTheme(ThemeData base) => base.copyWith(
  appBarTheme: base.appBarTheme.copyWith(
    centerTitle: false,
    toolbarHeight: 72,
    titleTextStyle: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w700,
    ),
  ),
  navigationBarTheme: base.navigationBarTheme.copyWith(
    height: 72,
    indicatorShape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
  ),
  cardTheme: base.cardTheme.copyWith(
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
);
