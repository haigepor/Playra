import 'dart:convert';
import 'plugins.dart';

bool isManagedAnime(Plugin plugin) =>
    plugin.sourceConfig['managedBy'] == 'playra-anifive';

/// 来源以固定运行路由识别，兼容避让自定义规则后的本地名称/ID。
bool isManagedAnimeSource(Plugin plugin, String source) =>
    isManagedAnime(plugin) &&
    plugin.searchApiConfig.request.url ==
        'https://source-runtime.playra.invalid/v1/adapters/anifive-$source/search';

bool matchesAnimeHistorySource(Plugin plugin, String name, String detailUrl) {
  const legacy = {
    'dm84': ('a', 'dmbus.cc'),
    'mxdm': ('b', 'dcc3.com'),
    'akianime': ('c', 'akianime.cc'),
    'moonci': ('d', 'moonci.com'),
    'aafun': ('d', 'moonci.com'),
  };
  final origin = legacy[name.toLowerCase()];
  if (origin != null) {
    final host = Uri.tryParse(plugin.baseUrl)?.host.replaceFirst('www.', '');
    // 旧相对链接没有记录域名，不能把它绑定到后来导入的同名异站规则。
    if (Uri.tryParse(detailUrl)?.hasAuthority == false && host != origin.$2) {
      return false;
    }
    if (host == origin.$2 && isManagedAnimeSource(plugin, origin.$1)) {
      return true;
    }
  }
  return plugin.name == name;
}

/// 只迁移与发布快照一致的旧规则；同名自定义项保留并为 SDK 分配独立身份。
List<Plugin> migrateBundledAnime(
  List<Plugin> installed,
  List<Plugin> legacy,
  List<Plugin> bundled,
) {
  Map<String, dynamic> comparable(Plugin plugin) =>
      Map.of(plugin.toJson())..remove('sourceId');
  Object? canonical(Object? value) {
    if (value is Map) {
      return {
        for (final key in value.keys.map((k) => k.toString()).toList()..sort())
          key: canonical(value[key]),
      };
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  final originals = {for (final p in legacy) pluginNameKey(p.name): p};
  bool unchanged(Plugin plugin) {
    final original = originals[pluginNameKey(plugin.name)];
    return original != null &&
        jsonEncode(canonical(comparable(plugin))) ==
            jsonEncode(canonical(comparable(original)));
  }

  final pending = {for (final p in bundled) pluginNameKey(p.name): p};
  final result = <Plugin>[];
  final retained = installed.where((p) => !unchanged(p)).toList();
  Plugin replacement(Plugin bundled, [Plugin? previous]) {
    final copy = Plugin.fromJson(bundled.toJson());
    if (previous != null) copy.sourceId = previous.providerId;
    if (retained.any(
      (p) =>
          p.providerId == copy.providerId ||
          pluginNameKey(p.name) == pluginNameKey(copy.name),
    )) {
      copy.sourceId = 'anifive-${copy.providerId}';
      copy.name = '${copy.name} SDK';
      var suffix = 2;
      while (retained.any(
        (p) =>
            p.providerId == copy.providerId ||
            pluginNameKey(p.name) == pluginNameKey(copy.name),
      )) {
        copy.sourceId = 'anifive-${bundled.providerId}-$suffix';
        copy.name = '${bundled.name} SDK $suffix';
        suffix++;
      }
    }
    return copy;
  }

  for (final plugin in installed) {
    if (isManagedAnime(plugin)) {
      final route = plugin.searchApiConfig.request.url;
      pending.removeWhere((_, p) => p.searchApiConfig.request.url == route);
      result.add(plugin);
    } else if (unchanged(plugin)) {
      final next = pending.remove(pluginNameKey(plugin.name));
      if (next != null) result.add(replacement(next, plugin));
    } else {
      result.add(plugin);
    }
  }
  result.addAll(pending.values.map((p) => replacement(p)));
  return result;
}
