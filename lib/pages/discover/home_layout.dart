import 'package:flutter/material.dart';

import 'package:kazumi/presentation/theme/playra_tokens.dart';

/// Responsive layout contract for the discovery/home page.
///
/// The phone and tablet shells are intentionally different products:
/// phones use the bottom navigation and a three-row header, while tablets
/// keep the fixed side rail and a single-row toolbar. Using `shortestSide`
/// (instead of only width) also keeps a landscape phone from being mistaken
/// for a tablet.
enum HomeLayoutKind { phone, tabletPortrait, tabletLandscape }

@immutable
class HomeLayoutMetrics {
  const HomeLayoutMetrics({
    required this.kind,
    required this.gutter,
    required this.sectionGap,
    required this.cardGap,
    required this.sectionColumns,
    required this.sectionItemCount,
    required this.heroFraction,
    required this.heroMinHeight,
    required this.heroMaxHeight,
    required this.contentMaxWidth,
    this.compactHeight = false,
  });

  final HomeLayoutKind kind;
  final double gutter;
  final double sectionGap;
  final double cardGap;
  final int sectionColumns;
  final int sectionItemCount;
  final double heroFraction;
  final double heroMinHeight;
  final double heroMaxHeight;
  final double contentMaxWidth;

  /// Phone layouts on short screens use denser header, hero and section
  /// spacing while keeping the same information architecture.
  final bool compactHeight;

  bool get isPhone => kind == HomeLayoutKind.phone;
  bool get isPhoneCompact => isPhone && compactHeight;
  bool get isTabletLandscape => kind == HomeLayoutKind.tabletLandscape;
  bool get showSideRail => !isPhone;
  bool get showRankingPanel => isTabletLandscape;
  bool get hasThreeRowHeader => isPhone;

  double get headerTopPadding => isPhoneCompact ? 6 : 8;
  double get brandRowHeight => isPhoneCompact ? 38 : 44;
  double get searchHeight => isPhoneCompact ? 40 : 48;
  double get categoryRowHeight => isPhoneCompact ? 40 : 48;
  double get categoryVisualHeight => isPhoneCompact ? 34 : 40;
  double get headerGap => isPhoneCompact ? 6 : 8;
  double get heroTopPadding => isPhoneCompact ? 4 : 8;
  double get vipTopPadding => isPhoneCompact ? 8 : 12;
  double get vipMinHeight => isPhoneCompact ? 44 : 52;

  static const HomeLayoutMetrics phone = HomeLayoutMetrics(
    kind: HomeLayoutKind.phone,
    gutter: 16,
    sectionGap: 20,
    cardGap: 8,
    sectionColumns: 3,
    sectionItemCount: 3,
    heroFraction: .78,
    heroMinHeight: 170,
    heroMaxHeight: 240,
    contentMaxWidth: double.infinity,
  );

  static const HomeLayoutMetrics phoneCompact = HomeLayoutMetrics(
    kind: HomeLayoutKind.phone,
    gutter: 14,
    sectionGap: 16,
    cardGap: 8,
    sectionColumns: 3,
    sectionItemCount: 3,
    heroFraction: .78,
    heroMinHeight: 145,
    heroMaxHeight: 190,
    contentMaxWidth: double.infinity,
    compactHeight: true,
  );

  static const HomeLayoutMetrics tabletPortrait = HomeLayoutMetrics(
    kind: HomeLayoutKind.tabletPortrait,
    gutter: 24,
    sectionGap: 32,
    cardGap: 16,
    sectionColumns: 3,
    sectionItemCount: 3,
    heroFraction: .66,
    heroMinHeight: 280,
    heroMaxHeight: 420,
    contentMaxWidth: 1000,
  );

  static const HomeLayoutMetrics tabletLandscape = HomeLayoutMetrics(
    kind: HomeLayoutKind.tabletLandscape,
    gutter: 32,
    sectionGap: 36,
    cardGap: 20,
    sectionColumns: 4,
    sectionItemCount: 4,
    heroFraction: .78,
    heroMinHeight: 280,
    heroMaxHeight: 440,
    contentMaxWidth: 1200,
  );

  static HomeLayoutMetrics of(BuildContext context) =>
      resolve(MediaQuery.sizeOf(context));

  static HomeLayoutMetrics resolve(Size size) {
    if (size.shortestSide < PlayraLayout.compactWidth) {
      return size.height < 720 ? phoneCompact : phone;
    }
    return size.width > size.height ? tabletLandscape : tabletPortrait;
  }
}
