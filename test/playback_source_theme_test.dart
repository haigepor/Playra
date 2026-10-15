import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/home_theme.dart';
import 'package:kazumi/presentation/modern/player/player_theme.dart';
import 'package:kazumi/presentation/modern/player/sdk_source_widgets.dart';

void main() {
  for (final material3 in [false, true]) {
    testWidgets(
      'playback inherits new secondary page tokens with Material3=$material3',
      (tester) async {
        late ThemeData theme;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.light(useMaterial3: material3),
            home: ModernPlayerScope(
              child: Builder(
                builder: (context) {
                  theme = Theme.of(context);
                  return Scaffold(
                    body: PlaybackSdkChip(
                      name: 'AniFive',
                      selected: true,
                      onSelected: () {},
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final colors = modernHomeColors(Brightness.dark);
        expect(theme.colorScheme.surfaceContainerLow, colors.card);
        expect(
          theme.canvasColor,
          colors.card,
          reason: 'Chip的Material底层也须继承新页面表面，避免半透明选中态叠在浅底上',
        );
        expect(theme.textTheme.titleLarge?.fontSize, 16);
        expect(theme.iconTheme.size, 20);
        expect(theme.bottomSheetTheme.modalBackgroundColor, colors.card);
        final chip = tester.widget<ChoiceChip>(find.byType(ChoiceChip));
        final selected = {WidgetState.selected};
        final actual =
            chip.color?.resolve(selected) ??
            theme.chipTheme.color?.resolve(selected);
        expect(
          actual,
          theme.chipTheme.color?.resolve(selected),
          reason: 'SDK标签须继承新页面选中态，不再自定另一组透明度',
        );
        final inks = tester.widgetList<Ink>(
          find.descendant(of: find.byType(RawChip), matching: find.byType(Ink)),
        );
        expect(
          inks.any(
            (ink) => (ink.decoration as ShapeDecoration?)?.color == actual,
          ),
          isTrue,
          reason: '须检查实际绘制色，Material2不会读取Chip的状态颜色',
        );
      },
    );
  }
}
