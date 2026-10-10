import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_service.dart';

class FixtureExecutor implements RuleRequestExecutor {
  final requests = <PreparedRuleRequest>[];
  @override
  Future<String> execute(
    PreparedRuleRequest request,
    RuleExecutionConfig config, {
    RuleCancelToken? cancelToken,
  }) async {
    requests.add(request);
    if (request.url.contains('search')) {
      return jsonEncode({
        'data': [
          {'name': '测试第一季', 'url': 'content-7'},
        ],
      });
    }
    return jsonEncode({
      'data': {
        'roads': [
          {
            'name': '线路一',
            'episodes': [
              {'name': 'SP', 'url': '/play/7'},
            ],
          },
        ],
      },
    });
  }
}

Map<String, dynamic> fixtureRule() => {
  'api': '8',
  'name': 'Fixture',
  'version': '1.0',
  'baseURL': 'https://example.org/',
  'searchMode': 'api',
  'chapterMode': 'api',
  'searchApiConfig': {
    'request': {'url': 'https://example.org/search'},
  },
  'chapterApiConfig': {
    'request': {'url': 'https://example.org/detail/@source'},
  },
};

void main() {
  test(
    'very large local pages return an empty collection without overflow',
    () {
      final page = SourcePage.local(
        [1, 2],
        page: 0x7fffffffffffffff,
        pageSize: 100,
      );
      expect(page.items, isEmpty);
      expect(page.pagination.hasMore, isFalse);
    },
  );
  test(
    'cancelled operations do not publish success or poison health',
    () async {
      final service = SourceService();
      final ctx = SourceContext();
      await expectLater(
        service.observe('fixture', 'resolve', ctx, () async {
          ctx.cancelToken.cancel();
          return 'late';
        }),
        throwsA(
          isA<SourceException>().having((e) => e.code, 'code', 'CANCELLED'),
        ),
      );
      expect(service.health('fixture', 'resolve'), isNull);
    },
  );
  test(
    'deadline cancels underlying work and records timeout separately',
    () async {
      final service = SourceService();
      final ctx = SourceContext(timeout: const Duration(milliseconds: 2));
      await expectLater(
        service.observe('fixture', 'episodes', ctx, () async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return 'late';
        }),
        throwsA(
          isA<SourceException>().having((e) => e.code, 'code', 'TIMEOUT'),
        ),
      );
      expect(ctx.cancelToken.isCancelled, isTrue);
      expect(service.health('fixture', 'episodes')?.errorCode, 'TIMEOUT');
      expect(service.health('fixture', 'search'), isNull);
    },
  );
  test(
    'upstream pagination cannot advertise fixed first-page requests',
    () async {
      final executor = FixtureExecutor();
      final service = SourceService(
        engine: RuleEngine(requestExecutor: executor),
      );
      final source = SourceDefinition.fromJson({
        ...fixtureRule(),
        'sourceConfig': {
          'searchPagination': {'enabled': true},
        },
      });
      await expectLater(
        service.search(source, 'x', page: 2),
        throwsA(
          isA<SourceException>().having((e) => e.code, 'code', 'INVALID_RULE'),
        ),
      );
      expect(executor.requests, isEmpty);
    },
  );
  test(
    'child deadlines do not cancel sibling requests and parent cancels children',
    () async {
      final parent = RuleCancelToken();
      final a = SourceContext(cancelToken: parent),
          b = SourceContext(cancelToken: parent);
      a.cancelToken.cancel('deadline');
      expect(parent.isCancelled, isFalse);
      expect(b.cancelToken.isCancelled, isFalse);
      parent.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(b.cancelToken.isCancelled, isTrue);
    },
  );
  test(
    'explicit identity and additive extensions round trip with old JSON',
    () {
      final json = {
        ...fixtureRule(),
        'sourceId': 'stable-1',
        'sourceConfig': {
          'searchPagination': {'enabled': true},
        },
        'customFutureField': {'x': 1},
      };
      final source = SourceDefinition.fromJson(json);
      expect(source.manifest.id, 'stable-1');
      expect(source.toJson(), json);
      expect(
        SourceDefinition.fromJson({...json, 'name': '改名后'}).manifest.id,
        'stable-1',
      );
    },
  );
  test('legacy identity survives domain and revision changes', () {
    final a = SourceDefinition.fromJson(fixtureRule());
    final b = SourceDefinition.fromJson({
      ...fixtureRule(),
      'baseURL': 'https://new.example.org/',
      'version': '2.0',
    });
    expect(a.manifest.id, b.manifest.id);
    expect(a.toJson()['searchApiConfig'], fixtureRule()['searchApiConfig']);
  });
  test(
    'opaque refs preserve IDs that are not URLs and special episode labels',
    () async {
      final executor = FixtureExecutor();
      final service = SourceService(
        engine: RuleEngine(requestExecutor: executor),
      );
      final source = SourceDefinition.fromJson(fixtureRule());
      final result = await service.search(source, '测试');
      expect(result.items.single.ref.rawRef, 'content-7');
      expect(result.pagination.mode, 'local');
      final lines = await service.lines(source, result.items.single.ref);
      expect(
        executor.requests.last.url,
        'https://example.org/detail/content-7',
      );
      expect(lines.single.episodes.single.title, 'SP');
      expect(lines.single.toRoad().identifier, ['SP']);
      expect(service.health(source.manifest.id, 'search')?.status, 'success');
      expect(service.health(source.manifest.id, 'resolve'), isNull);
    },
  );
  test('foreign source references are rejected before executing', () async {
    final executor = FixtureExecutor();
    final service = SourceService(
      engine: RuleEngine(requestExecutor: executor),
    );
    await expectLater(
      service.lines(
        SourceDefinition.fromJson(fixtureRule()),
        const SourceRef(providerId: 'another', rawRef: 'content-7'),
      ),
      throwsA(isA<SourceException>()),
    );
    expect(executor.requests, isEmpty);
  });
  test(
    'local pagination validates input and reports only fetched collection',
    () {
      final page = SourcePage.local(const [1, 2, 3], page: 2, pageSize: 2);
      expect(page.items, [3]);
      expect(page.pagination.hasMore, false);
      expect(page.pagination.total, 3);
      expect(
        () => SourcePage.local([1], page: 0),
        throwsA(isA<SourceException>()),
      );
    },
  );
}
