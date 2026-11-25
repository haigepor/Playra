import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/player_item_surface.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';

void main() {
  test('video subtitles use readable foreground and dark edge shadows', () {
    expect(playerSubtitleStyle.color, Colors.white);
    expect(playerSubtitleStyle.fontSize, PlayraType.title);
    expect(playerSubtitleStyle.shadows, isNotEmpty);
    expect(
      playerSubtitleStyle.shadows!.every((s) => s.color == Colors.black),
      isTrue,
    );
  });
}
