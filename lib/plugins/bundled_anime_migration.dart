import 'dart:convert';
import 'plugins.dart';

const kazumiRuleOrigins = {
  '7sefun': 'https://www.7sefun.top',
  'aafun': 'https://www.moonci.com',
  'AGE': 'https://www.agedm.io',
  'akianime': 'https://www.akianime.cc',
  'baimao': 'https://www.baimaodm.com',
  'dalvdm': 'https://www.sbdl.cc',
  'DM84': 'https://dmbus.cc',
  'ezdmw': 'https://m.ezdmw.org',
  'giriGiriLove': 'https://ani.girigirilove.com',
  'mgnacg': 'https://www.mgnacg.com',
  'moonci': 'https://www.moonci.com',
  'mutefun': 'https://www.2kdm.com',
  'MXdm': 'https://www.dcc3.com',
  'sorani': 'https://www.sorani.net',
  'xfdmneo': 'https://dm1.xfdm.pro',
  'xfdmnext': 'https://next.xifanacg.com',
};

/// 受管身份与官方站点同时匹配；同名自定义规则不自动加入 SDK。
String? managedKazumiName(Plugin plugin) {
  final name = plugin.sourceConfig['officialName'];
  final uri = Uri.tryParse(plugin.baseUrl);
  return plugin.sourceConfig['managedBy'] == 'playra-kazumi' &&
          name is String &&
          kazumiRuleOrigins.containsKey(name) &&
          uri?.hasAuthority == true &&
          const ['http', 'https'].contains(uri!.scheme) &&
          uri.userInfo.isEmpty &&
          uri.origin == kazumiRuleOrigins[name]
      ? name
      : null;
}

bool isManagedKazumi(Plugin plugin) => managedKazumiName(plugin) != null;

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
    if (host == origin.$2 &&
        (isManagedAnimeSource(plugin, origin.$1) ||
            managedKazumiName(plugin)?.toLowerCase() == name.toLowerCase())) {
      return true;
    }
  }
  return plugin.name == name;
}

/// 替换未编辑的四源/旧十六源；保留名称、来源 ID 和用户自定义项，重试幂等。
List<Plugin> migrateBundledKazumi(
  List<Plugin> installed,
  List<Plugin> legacy,
  List<Plugin> previousBundled,
  List<Plugin> bundled,
) {
  Object? canonical(Object? value) {
    if (value is Map) {
      return {
        for (final key in value.keys.map((k) => '$k').toList()..sort())
          key: canonical(value[key]),
      };
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  String signature(Plugin p, {bool renamed = false, bool metadata = false}) {
    final json = Map.of(p.toJson())..remove('sourceId');
    if (renamed) json.remove('name');
    if (metadata) json.remove('sourceConfig');
    return jsonEncode(canonical(json));
  }

  String? replacementName(Plugin plugin) {
    final managed = managedKazumiName(plugin);
    if (managed != null) return managed;
    for (final previous in previousBundled) {
      if (isManagedAnime(plugin) &&
          signature(plugin, renamed: true) ==
              signature(previous, renamed: true)) {
        return previous.name;
      }
    }
    for (final original in legacy) {
      if (signature(plugin) == signature(original)) return original.name;
    }
    for (final original in bundled) {
      if (signature(plugin, metadata: true) ==
              signature(original, metadata: true) &&
          plugin.sourceConfig.isEmpty) {
        return original.name;
      }
    }
    return null;
  }

  final replacements = <String, Plugin>{};
  final retained = <Plugin>[];
  for (final plugin in installed) {
    final name = replacementName(plugin);
    if (name == null || replacements.containsKey(name)) {
      retained.add(plugin);
    } else {
      replacements[name] = plugin;
    }
  }
  final result = <Plugin>[];
  final ids = retained.map((p) => p.providerId).toSet();
  final names = retained.map((p) => pluginNameKey(p.name)).toSet();
  for (final asset in bundled) {
    final previous = replacements[asset.sourceConfig['officialName']];
    final copy = Plugin.fromJson(asset.toJson());
    copy.sourceId = previous?.providerId ?? asset.providerId;
    if (previous != null) {
      copy.name = previous.name;
    }
    final originalId = copy.providerId, originalName = copy.name;
    var suffix = 0;
    while (ids.contains(copy.providerId) ||
        names.contains(pluginNameKey(copy.name))) {
      suffix++;
      final ending = suffix == 1 ? '' : ' $suffix';
      copy.sourceId = '$originalId-kazumi${suffix == 1 ? '' : '-$suffix'}';
      copy.name = '$originalName Kazumi$ending';
    }
    ids.add(copy.providerId);
    names.add(pluginNameKey(copy.name));
    result.add(copy);
  }
  return [...result, ...retained];
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
