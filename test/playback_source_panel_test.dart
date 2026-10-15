import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/player/sdk_source_widgets.dart';

void main() {
  testWidgets(
    'automatic mode stays visible while compact provider routes scroll',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: PlaybackLineSheet(
              sdkName: 'AniFive',
              onClose: () {},
              automaticOption: SdkLineOption(
                title: '自动选择',
                subtitle: '仅在当前 SDK 内优选',
                onTap: () {},
                automatic: true,
                selected: true,
              ),
              children: [
                const Text('DM84'),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (var i = 1; i <= 50; i++)
                      PlaybackRouteChip(
                        name: '线路 $i',
                        episodeCount: 1180,
                        onTap: () {},
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final automatic = find.text('自动选择');
      final initialY = tester.getTopLeft(automatic).dy;
      await tester.scrollUntilVisible(
        find.text('线路 50'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(automatic).dy, initialY);
      expect(find.text('线路 50'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shared source card exposes its own accessible action at 320px and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var opened = 0;
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: SingleChildScrollView(
                child: PlaybackSourcePanel(
                  groups: [
                    PlaybackSdkChip(
                      name: 'AniFive',
                      selected: true,
                      onSelected: () {},
                    ),
                  ],
                  summary: '手动 · MXdm / 真实线路 2',
                  automatic: false,
                  lineCount: 9,
                  selectorKey: const ValueKey('lines'),
                  onShowLines: () {
                    opened++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final action = find.byKey(const ValueKey('lines'));
      expect(
        tester.getSemantics(action).getSemanticsData().flagsCollection.isButton,
        isTrue,
      );
      await tester.tap(action);
      expect(opened, 1);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}
