import 'package:flutter/material.dart';

/// 新版采用局部品牌色板，沿用用户字体与系统辅助功能设置。
ThemeData modernTheme(ThemeData base) => base.copyWith(
  appBarTheme: base.appBarTheme.copyWith(
    centerTitle: false,
    toolbarHeight: 56,
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
