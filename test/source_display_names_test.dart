import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/source_display_names.dart';

void main() {
  test(
    'anime sources share a category and Mio anime is explicitly a fallback',
    () {
      expect(playbackSourceName('lumina', 'Lumina'), '动漫 · Lumina');
      expect(playbackSourceName('anifive', 'AniFive'), '已移除来源（记录保留）');
      expect(
        playbackSourceName('miomedia', 'miomedia', anime: true),
        '已移除来源（记录保留）',
      );
      expect(playbackSourceName('miomedia', 'miomedia'), '已移除来源（记录保留）');
      expect(playbackSourceName('custom-id', '自定义站'), '自定义站');
    },
  );
}
