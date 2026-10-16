import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/widgets/modern_page_art.dart';

void main() {
  testWidgets('small decorative art decodes at display density', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: ModernMaterialArt(
            asset: 'modern-cinema-header-art.png',
            width: 180,
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as ResizeImage).width, 360);
    expect(tester.getSize(find.byType(ModernMaterialArt)), const Size(180, 60));
  });
}
