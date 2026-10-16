import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/source_display_names.dart';

void main() {
  test(
    'anime sources share a category and Mio anime is explicitly a fallback',
    () {
      expect(playbackSourceName('lumina', 'Lumina'), '动漫 · Lumina');
      expect(playbackSourceName('anifive', 'AniFive'), '动漫 · AniFive');
      expect(
        playbackSourceName('miomedia', 'miomedia', anime: true),
        '动漫备用 · MioMedia',
      );
      expect(playbackSourceName('miomedia', 'miomedia'), '影视 · MioMedia');
      expect(playbackSourceName('custom-id', '自定义站'), '自定义站');
    },
  );
}
