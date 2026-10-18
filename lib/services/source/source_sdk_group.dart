import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/bundled_anime_migration.dart';
import 'source_display_names.dart';

/// SDK 分组只改变展示与自动尝试范围，不改变历史使用的 providerId。
/// 新 SDK 在此注册受管理标记和运行路由；自定义规则默认各自独立。
String playbackSdkId(Plugin plugin) {
  if (isManagedKazumi(plugin)) return 'kazumi';
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

const kazumiAutomaticSourceOrder = ['akianime', 'mutefun', 'giriGiriLove'];

/// 只限制受管 Kazumi 的自动入口；本地改名不改变官方身份，手动目录仍保留全部规则。
int? automaticPlaybackPriority(Plugin plugin) {
  final name = managedKazumiName(plugin);
  if (name == null) return 0;
  final priority = kazumiAutomaticSourceOrder.indexOf(name);
  return priority < 0 ? null : priority;
}

List<Plugin> automaticPlaybackSources(Iterable<Plugin> plugins) {
  final result = plugins
      .where((p) => automaticPlaybackPriority(p) != null)
      .toList();
  final order = {for (var i = 0; i < result.length; i++) result[i]: i};
  result.sort((a, b) {
    final priority = automaticPlaybackPriority(
      a,
    )!.compareTo(automaticPlaybackPriority(b)!);
    return priority != 0 ? priority : order[a]!.compareTo(order[b]!);
  });
  return result;
}

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
          playbackSourceName(entry.key, entry.value.first.name, anime: true),
          List.unmodifiable(entry.value),
        ),
    ];
  }
}
