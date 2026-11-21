import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/discover/home_layout.dart';

void main() {
  test('phone portrait uses phone layout', () {
    expect(
      HomeLayoutMetrics.resolve(const Size(390, 844)).kind,
      HomeLayoutKind.phone,
    );
  });

  test('landscape phone is still a phone', () {
    final metrics = HomeLayoutMetrics.resolve(const Size(844, 390));
    expect(metrics.kind, HomeLayoutKind.phone);
    expect(metrics.showSideRail, isFalse);
  });

  test('short phone uses compact vertical metrics', () {
    final metrics = HomeLayoutMetrics.resolve(const Size(360, 640));
    expect(metrics.kind, HomeLayoutKind.phone);
    expect(metrics.isPhoneCompact, isTrue);
    expect(metrics.brandRowHeight, lessThan(44));
    expect(metrics.searchHeight, lessThan(48));
    expect(metrics.heroMaxHeight, lessThan(240));
  });

  test('tablet portrait uses three-column layout', () {
    final metrics = HomeLayoutMetrics.resolve(const Size(853, 1280));
    expect(metrics.kind, HomeLayoutKind.tabletPortrait);
    expect(metrics.sectionColumns, 3);
    expect(metrics.showSideRail, isTrue);
  });

  test('tablet landscape uses four-column layout and ranking panel', () {
    final metrics = HomeLayoutMetrics.resolve(const Size(1280, 853));
    expect(metrics.kind, HomeLayoutKind.tabletLandscape);
    expect(metrics.sectionColumns, 4);
    expect(metrics.showRankingPanel, isTrue);
  });
}
