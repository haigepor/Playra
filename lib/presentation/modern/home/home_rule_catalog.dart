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

  static Future<HomeRuleCatalog> load(Iterable<Plugin> installed) async =>
      const HomeRuleCatalog();
}
