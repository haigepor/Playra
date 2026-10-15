import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/search/plugin_search_module.dart';
import 'package:kazumi/plugins/api_rule_config.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/services/plugin/api_rule_engine.dart';
import 'package:kazumi/services/source/source_service.dart';

class CoverFixtureExecutor implements RuleRequestExecutor {
  CoverFixtureExecutor(this.items);
  final List<Map<String, Object?>> items;

  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    RuleCancelToken? cancelToken,
  }) async => jsonEncode({'data': items});
}

Map<String, dynamic> coverRule({bool includeCoverPath = true}) => {
  'api': '8',
  'type': 'anime',
  'name': 'Cover fixture',
  'sourceId': 'cover-fixture',
  'baseURL': 'https://source.example/',
  'searchMode': 'api',
  'searchApiConfig': {
    'request': {'url': 'https://source.example/search'},
    'listPath': r'$.data[*]',
    'namePath': r'$.name',
    'sourcePath': r'$.url',
    if (includeCoverPath) 'coverPath': r'$.cover',
  },
};

void main() {
  const parser = ApiRuleStrategy();

  test('old search configurations and items retain their empty cover default', () {
    final config = ApiSearchConfig.fromJson({
      'listPath': r'$.data[*]',
      'namePath': r'$.name',
      'sourcePath': r'$.url',
    });
    final parsed = parser.parseSearch(
      jsonEncode({
        'data': [
          {'name': '旧规则作品', 'url': '/detail/41'},
        ],
      }),
      config,
    );

    expect(config.coverPath, isEmpty);
    expect(config.toJson().containsKey('coverPath'), isFalse);
    expect(parsed.items.single.name, '旧规则作品');
    expect(parsed.items.single.coverUrl, isEmpty);
    expect(SearchItem.fromJson({'name': '旧项', 'src': '41'}).coverUrl, isEmpty);
  });

  test('configured coverPath survives plugin JSON round trips', () {
    final plugin = Plugin.fromJson(coverRule());
    final restored = Plugin.fromJson(jsonDecode(jsonEncode(plugin.toJson())));

    expect(restored.searchApiConfig.coverPath, r'$.cover');
    expect(restored.searchApiConfig.toJson()['coverPath'], r'$.cover');
  });

  test('cover extraction remains opt in for legacy API rules', () {
    final parsed = parser.parseSearch(
      jsonEncode({
        'data': [
          {'name': '旧规则', 'url': '/41', 'cover': 'https://cdn.example/41.jpg'},
        ],
      }),
      ApiSearchConfig(),
    );

    expect(parsed.items.single.coverUrl, isEmpty);
  });

  test('each search node keeps its own cover including an absent middle cover', () {
    final parsed = parser.parseSearch(
      jsonEncode({
        'data': [
          {'name': '作品甲', 'url': '/41', 'cover': 'https://cdn.example/41.jpg?w=300&h=450'},
          {'name': '作品乙', 'url': '/42'},
          {'name': '作品丙', 'url': '/43', 'cover': 'http://cdn.example/43.jpg'},
        ],
      }),
      ApiSearchConfig(coverPath: r'$.cover'),
    );

    expect(parsed.items.map((item) => item.src), ['/41', '/42', '/43']);
    expect(parsed.items.map((item) => item.coverUrl), [
      'https://cdn.example/41.jpg?w=300&h=450',
      '',
      'http://cdn.example/43.jpg',
    ]);
  });

  test('invalid image URLs are discarded without removing otherwise valid search hits', () {
    final invalid = <Object?>[
      'javascript:alert(1)',
      'data:image/png;base64,AAAA',
      'file:///tmp/image.jpg',
      'https://user:password@cdn.example/image.jpg',
      'https://cdn.example:invalid/image.jpg',
      'http://[broken/image.jpg',
      '/not-normalized.jpg',
      '//cdn.example/not-normalized.jpg',
      '',
      null,
    ];
    for (final cover in invalid) {
      final parsed = parser.parseSearch(
        jsonEncode({
          'data': [
            {'name': '可搜索作品', 'url': '/41', 'cover': cover},
          ],
        }),
        ApiSearchConfig(coverPath: r'$.cover'),
      );

      expect(parsed.items, hasLength(1), reason: '$cover');
      expect(parsed.items.single.coverUrl, isEmpty, reason: '$cover');
    }
  });

  test('cover JSONPath obeys the existing restricted expression grammar', () {
    expect(
      () => parser.validateSearchConfig(ApiSearchConfig(coverPath: r'$..cover')),
      throwsA(isA<ApiRuleFormatException>()),
    );
  });

  test('SourceService carries valid covers and preserves null for coverless results', () async {
    final service = SourceService(
      engine: RuleEngine(
        requestExecutor: CoverFixtureExecutor([
          {'name': '作品甲', 'url': '/41', 'cover': 'https://cdn.example/41.jpg'},
          {'name': '作品乙', 'url': '/42'},
          {'name': '作品丙', 'url': '/43', 'cover': 'javascript:alert(1)'},
        ]),
      ),
    );
    final result = await service.search(SourceDefinition.fromJson(coverRule()), '作品');

    expect(result.items.map((item) => item.title), ['作品甲', '作品乙', '作品丙']);
    expect(result.items.map((item) => item.coverUrl), ['https://cdn.example/41.jpg', null, null]);
    expect(result.items.first.toJson()['coverUrl'], 'https://cdn.example/41.jpg');
    expect(result.items.first.ref.providerId, 'cover-fixture');
  });

  test('a legacy API source stays searchable without coverPath or image fields', () async {
    final service = SourceService(
      engine: RuleEngine(
        requestExecutor: CoverFixtureExecutor([
          {'name': '旧来源作品', 'url': '/legacy'},
        ]),
      ),
    );
    final result = await service.search(
      SourceDefinition.fromJson(coverRule(includeCoverPath: false)),
      '作品',
    );

    expect(result.items.single.title, '旧来源作品');
    expect(result.items.single.ref.rawRef, '/legacy');
    expect(result.items.single.coverUrl, isNull);
  });
}
