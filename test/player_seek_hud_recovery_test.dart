import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_adjustment_hud.dart';

void main() {
  for (final disableAnimations in [true, false]) {
    testWidgets(
      'seek cancellation hint follows state, animations disabled: $disableAnimations',
      (tester) async {
        tester.view.physicalSize = const Size(320, 240);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        Widget hud(bool cancelPending) => MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 240),
              textScaler: TextScaler.linear(2),
            ),
            child: Center(
              child: PlayerSeekHud(
                visible: true,
                currentPosition: const Duration(seconds: 40),
                playerPosition: const Duration(seconds: 30),
                duration: const Duration(minutes: 2),
                direction: 1,
                cancelPending: cancelPending,
                disableAnimations: disableAnimations,
              ),
            ),
          ),
        );

        await tester.pumpWidget(hud(false));
        await tester.pumpAndSettle();
        expect(find.text('+10 秒'), findsOneWidget);
        expect(find.text('移回画面继续调整'), findsNothing);
        await tester.pumpWidget(hud(true));
        await tester.pumpAndSettle();
        expect(find.text('松开取消'), findsOneWidget);
        expect(find.text('移回画面继续调整'), findsOneWidget);
        await tester.pumpWidget(hud(false));
        await tester.pumpAndSettle();
        expect(find.text('+10 秒'), findsOneWidget);
        expect(find.text('移回画面继续调整'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
