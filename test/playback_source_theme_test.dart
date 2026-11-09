import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;
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
        final button = find.descendant(
          of: find.byType(PlaybackSdkChip),
          matching: find.byType(f.FButton),
        );
        expect(button, findsOneWidget);
        expect(tester.widget<f.FButton>(button).selected, isTrue);
        final forui = f.FTheme.of(tester.element(button));
        final expected = forui.buttonStyles.secondary.lg.decoration.resolve({
          f.FTappableVariant.selected,
        });
        final surfaces = tester.widgetList<DecoratedBox>(
          find.descendant(of: button, matching: find.byType(DecoratedBox)),
        );
        expect(
          surfaces.any((surface) => surface.decoration == expected),
          isTrue,
          reason: 'Source selections use the actual Forui selected surface',
        );
        expect(find.byType(ChoiceChip), findsNothing);
      },
    );
  }
}
