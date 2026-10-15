import 'package:kazumi/plugins/plugins.dart';

/// SDK 分组只改变展示与自动尝试范围，不改变历史使用的 providerId。
/// 新 SDK 在此注册受管理标记和运行路由；自定义规则默认各自独立。
String playbackSdkId(Plugin plugin) {
  final uri = Uri.tryParse(plugin.chapterApiConfig.request.url);
  if (plugin.sourceConfig['managedBy'] == 'playra-anifive' &&
      uri?.host == 'source-runtime.playra.invalid' &&
      RegExp(
        r'^/v1/adapters/anifive-[abcd]/episodes$',
      ).hasMatch(uri?.path ?? '')) {
    return 'anifive';
  }
  return 'rule:${plugin.providerId}';
}

List<Plugin> samePlaybackSdk(Plugin selected, Iterable<Plugin> plugins) =>
    plugins.where((p) => playbackSdkId(p) == playbackSdkId(selected)).toList();

class PlaybackSourceGroup {
  const PlaybackSourceGroup(this.id, this.name, this.plugins);
  final String id, name;
  final List<Plugin> plugins;

  static List<PlaybackSourceGroup> fromPlugins(Iterable<Plugin> plugins) {
    final groups = <String, List<Plugin>>{};
    for (final plugin in plugins) {
      (groups[playbackSdkId(plugin)] ??= []).add(plugin);
    }
    return [
      for (final entry in groups.entries)
        PlaybackSourceGroup(
          entry.key,
          entry.key == 'anifive' ? 'AniFive' : entry.value.first.name,
          List.unmodifiable(entry.value),
        ),
    ];
  }
}
