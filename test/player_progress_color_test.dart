import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_progress_bar.dart';

void main() {
  testWidgets('buffered segment is visibly distinct from unbuffered track', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.deepPurple),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: 300,
                height: 48,
                child: PlayerProgressBar(
                  progress: const Duration(seconds: 25),
                  buffered: const Duration(seconds: 50),
                  total: const Duration(seconds: 100),
                  sideLabels: false,
                  onDragStart: () {},
                  onDragUpdate: (_) {},
                  onDragEnd: (_) {},
                  onSeek: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      List<int> pixel(int x, int y) {
        final start = (y * image.width + x) * 4;
        return List.generate(4, (i) => bytes.getUint8(start + i));
      }

      expect(pixel(120, 24), isNot(equals(pixel(260, 24))));
      image.dispose();
    });
  });
}
