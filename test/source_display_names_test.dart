import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/source_display_names.dart';
import 'package:kazumi/services/storage/sdk_library_models.dart';

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
  test('second source never leaks its wire id into library records', () {
    const record = SdkLibraryRecord(
      providerId: 'whisklet',
      contentId: '7',
      title: '偏爱之恋2',
    );
    // 个人库与播放源行共用一张名称表，接口 id 不得直接展示。
    expect(playbackSourceName('whisklet', 'whisklet'), 'Whisklet');
    expect(record.sourceName, 'Whisklet');
  });
}
