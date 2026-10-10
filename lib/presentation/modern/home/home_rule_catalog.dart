import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:kazumi/services/source/source_service.dart';
import 'package:kazumi/services/source/source_directory.dart';
import 'package:kazumi/services/plugin/rule_engine_runtime_flutter.dart';
import 'package:kazumi/plugins/plugins.dart';

class HomeRuleEntry {
  const HomeRuleEntry(this.title, this.url, this.group);
  final String title, url, group;
}

class HomeRuleCatalog {
  const HomeRuleCatalog({
    this.name = '',
    this.entries = const [],
    this.failures = const [],
    this.elapsedMs = 0,
  });
  final String name;
  final List<HomeRuleEntry> entries;
  final List<String> failures;
  final int elapsedMs;

  /// 只去除标点与明确画质标记，保留季、篇、剧场版等身份信息。
  static String titleKey(String title) {
    const numbers = {
      '一': '1',
      '二': '2',
      '三': '3',
      '四': '4',
      '五': '5',
      '六': '6',
      '七': '7',
      '八': '8',
      '九': '9',
      '十': '10',
    };
    return title
        .toLowerCase()
        .replaceAll(
          RegExp(r'\[(?:1080p|720p|高清|中字)\]', caseSensitive: false),
          '',
        )
        .replaceAllMapped(
          RegExp(r'第([一二三四五六七八九十])季'),
          (m) => '第${numbers[m[1]]}季',
        )
        .replaceAll(RegExp(r'[^a-z0-9\u3040-\u30ff\u3400-\u9fff]'), '');
  }

  static Future<HomeRuleCatalog> load(Iterable<Plugin> installed) async {
    final registry = SourceDirectoryRegistry(
      executor: PlatformRuleRequestExecutor(),
    );
    final supported = installed
        .map((p) => SourceDefinition.fromJson(p.toJson()))
        .where(registry.supports)
        .toList();
    if (supported.isEmpty) {
      // 只读内置配置，不写入用户规则；展示层不识别任何站点名称。
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final path in manifest.listAssets().where(
        (p) => p.startsWith('assets/plugins/') && p.endsWith('.json'),
      )) {
        final source = SourceDefinition.fromJson(
          jsonDecode(await rootBundle.loadString(path)),
          origin: 'bundled',
        );
        if (registry.supports(source)) supported.add(source);
      }
    }
    supported.sort(
      (a, b) => registry.priority(a).compareTo(registry.priority(b)),
    );
    final failures = <String>[];
    for (final source in supported) {
      try {
        final result = await registry.load(source);
        failures.addAll(result.failures);
        return HomeRuleCatalog(
          name: result.name,
          entries: result.items
              .map(
                (e) => HomeRuleEntry(
                  e.title,
                  e.ref.rawRef,
                  e.classification.rawCategory ?? 'all',
                ),
              )
              .toList(),
          failures: failures,
          elapsedMs: result.elapsedMs,
        );
      } catch (_) {
        failures.add('${source.manifest.name}:catalog');
      }
    }
    return HomeRuleCatalog(failures: failures);
  }
}
