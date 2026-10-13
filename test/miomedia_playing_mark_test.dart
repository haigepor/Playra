import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_playing_mark.dart';

void main() {
  List<double> bars(WidgetTester tester) => List.generate(
    3,
    (i) => tester.getSize(find.byKey(ValueKey('mio-playing-bar-$i'))).height,
  );
  Future<void> mount(
    WidgetTester tester,
    bool active, {
    bool reduced = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Center(
          child: MioPlayingMark(active: active, color: Colors.purple),
        ),
      ),
    ),
  );
  testWidgets('bar motion freezes on pause without changing bounds', (
    tester,
  ) async {
    await mount(tester, true);
    final before = bars(tester);
    await tester.pump(const Duration(milliseconds: 210));
    expect(bars(tester), isNot(before));
    await mount(tester, false);
    final frozen = bars(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(bars(tester), frozen);
    expect(tester.getSize(find.byType(MioPlayingMark)), const Size(14, 14));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
  testWidgets('reduced motion keeps a playing marker static', (tester) async {
    await mount(tester, true, reduced: true);
    final before = bars(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(bars(tester), before);
    expect(tester.binding.transientCallbackCount, 0);
  });
}
