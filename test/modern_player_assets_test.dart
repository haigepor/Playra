import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('six player assets render at their actual narrow-phone sizes', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const assets = <String, Size>{
      'placeholder': Size(320, 180),
      'poster-placeholder': Size(60, 84),
      'empty-source': Size(160, 112),
      'empty-discussion': Size(160, 112),
      'playing-mark': Size(14, 14),
      'detail-decoration': Size(288, 96),
    };
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Column(
            children: [
              for (final entry in assets.entries)
                SvgPicture.asset(
                  'assets/images/modern-player-${entry.key}.svg',
                  width: entry.value.width,
                  height: entry.value.height,
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgPicture), findsNWidgets(6));
    expect(tester.takeException(), isNull);
  });
}
