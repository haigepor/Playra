import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/source/source_sdk_group.dart';

void main() {
  Plugin bundled(String file) => Plugin.fromJson(
    jsonDecode(File('assets/plugins/$file.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  test('four managed adapters share one SDK without changing provider IDs', () {
    final rules = ['DM84', 'MXdm', 'akianime', 'moonci'].map(bundled).toList();
    final groups = PlaybackSourceGroup.fromPlugins(rules);
    expect(groups, hasLength(1));
    expect(groups.single.id, 'anifive');
    expect(groups.single.name, '动漫 · AniFive');
    expect(groups.single.plugins.map((p) => p.providerId), [
      'dm84',
      'mxdm',
      'akianime',
      'moonci',
    ]);
  });
  test('renamed custom rules cannot join managed SDK by display name', () {
    final managed = bundled('DM84');
    final custom = Plugin.fromJson(managed.toJson())
      ..sourceId = 'my-rule'
      ..sourceConfig.remove('managedBy');
    expect(playbackSdkId(custom), 'rule:my-rule');
    expect(samePlaybackSdk(managed, [managed, custom]), [managed]);
  });
  test('managed marker alone cannot group an unrelated runtime', () {
    final custom = bundled('DM84');
    custom.chapterApiConfig.request.url = 'https://example.com/episodes';
    expect(playbackSdkId(custom), 'rule:dm84');
  });
}
