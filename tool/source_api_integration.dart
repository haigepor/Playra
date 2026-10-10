import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:kazumi/services/source/source_gateway.dart';
import 'package:kazumi/services/source/source_http_server.dart';
import 'package:kazumi/services/source/source_http_client.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/source/source_service.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  final fixture = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final gatewayUrl = 'http://127.0.0.1:${fixture.port}';
  final seenHeaders = <Map<String, dynamic>>[];
  final seenBodies = <Map<String, dynamic>>[];
  fixture.listen((request) async {
    request.response.headers.contentType = ContentType.json;
    if (request.uri.path == '/api/proxy') {
      final target = Uri.parse(request.uri.queryParameters['url']!);
      final encoded = request.headers.value('x-kazumi-headers')!;
      seenHeaders.add(
        jsonDecode(utf8.decode(base64Url.decode(encoded)))
            as Map<String, dynamic>,
      );
      if (request.method == 'POST') {
        seenBodies.add(
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>,
        );
      }
      if (target.path == '/bad') {
        request.response.statusCode = 500;
        request.response.write('{}');
      } else if (target.path == '/search') {
        final page = int.tryParse(target.queryParameters['page'] ?? '1') ?? 1;
        request.response.write(
          jsonEncode({
            'data': [
              {'name': '第一季 $page', 'url': 'content-$page'},
              {'name': 'SP', 'url': 'special'},
            ],
            'total': 4,
            'hasMore': page == 1,
          }),
        );
      } else if (target.path.startsWith('/detail/')) {
        request.response.write(
          jsonEncode({
            'data': {
              'roads': [
                {
                  'name': '主线路',
                  'episodes': [
                    {'name': 'SP', 'url': '/play/1'},
                    {'name': '第二集', 'url': '/play/2'},
                  ],
                },
              ],
            },
          }),
        );
      } else if (target.path == '/xpath-search') {
        request.response.write(
          '<html><body><div class="item"><a href="/v/2">动漫第二季</a></div></body></html>',
        );
      } else if (target.path == '/v/2') {
        request.response.write(
          '<html><body><ul class="road"><li><a href="/play/2">OVA</a></li></ul></body></html>',
        );
      } else if (target.path == '/media.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        request.response.write(
          '#EXTM3U\n/api/proxy?url=https%3A%2F%2Ffixture.example%2Fsegment.ts&headers=cookie-secret\n',
        );
      } else if (target.path == '/segment.ts') {
        request.response.write('segment');
      } else {
        request.response.write(
          '<a href="/cn">国漫</a><a class="title" href="/v/2">动漫第二季</a>',
        );
      }
    } else if (request.uri.path == '/api/parse') {
      await utf8.decoder.bind(request).join();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      request.response.write(
        jsonEncode({
          'url': 'https://fixture.example/media.m3u8',
          'format': 'hls',
        }),
      );
    } else if (request.uri.path == '/api/captcha') {
      final data = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
      request.response.write(
        jsonEncode(switch (data['action']) {
          'open' => {'id': 'fixture-challenge'},
          'poll' => {'done': true},
          'data' => {
            'cookie': 'verified=1',
            'userAgent': 'verified-agent',
            'html': '<html></html>',
          },
          _ => <String, dynamic>{},
        }),
      );
    }
    await request.response.close();
  });
  Map<String, dynamic> apiRule(String name) => {
    'api': '8',
    'name': name,
    'version': '1.0',
    'baseURL': 'https://fixture.example/',
    'searchMode': 'api',
    'chapterMode': 'api',
    'searchApiConfig': {
      'request': {'url': 'https://fixture.example/search'},
    },
    'chapterApiConfig': {
      'request': {'url': 'https://fixture.example/detail/@source'},
    },
  };
  final xpath = {
    'api': '5',
    'name': 'XPath',
    'baseURL': 'https://fixture.example/',
    'searchURL': 'https://fixture.example/xpath-search?wd=@keyword',
    'searchList': '//div',
    'searchName': '//a',
    'searchResult': '//a',
    'chapterRoads': '//ul',
    'chapterResult': '//a',
    'antiCrawlerConfig': {
      'enabled': true,
      'captchaType': 2,
      'captchaButton': '//button',
    },
    'sourceConfig': {
      'catalog': {'entrySelector': 'a.title[href]', 'detailPathPattern': '/v/'},
    },
  };
  final paged = apiRule('Paged');
  paged['searchApiConfig'] = {
    'request': {
      'url': 'https://fixture.example/search',
      'query': {'page': '@page', 'size': '@pageSize'},
    },
  };
  paged['sourceConfig'] = {
    'searchPagination': {
      'enabled': true,
      'totalPath': r'$.total',
      'hasMorePath': r'$.hasMore',
    },
  };
  final bad = apiRule('Bad');
  bad['searchApiConfig'] = {
    'request': {'url': 'https://fixture.example/bad'},
  };
  final posted = apiRule('Posted');
  posted['searchApiConfig'] = {
    'request': {
      'url': 'https://fixture.example/search',
      'method': 'POST',
      'bodyType': 'json',
      'body': {'q': '@keyword', 'enabled': true},
    },
  };
  final gateway = SourceGateway(Uri.parse(gatewayUrl));
  final api = SourceHttpServer(
    sources:
        [
              apiRule('API'),
              xpath,
              {...xpath, 'sourceId': 'another-xpath'},
              paged,
              bad,
              posted,
            ]
            .map((r) => SourceDefinition.fromJson(Map<String, dynamic>.from(r)))
            .toList(),
    gateway: gateway,
  );
  final port = await api.start(port: 0);
  final client = Dio(
    BaseOptions(baseUrl: 'http://127.0.0.1:$port', validateStatus: (_) => true),
  );
  final facade = SourceHttpClient('http://127.0.0.1:$port');
  var checks = 0;
  void verify(bool condition, String label) {
    check(condition, label);
    checks++;
  }

  try {
    final facadeSearch = await facade.search('测试', providerId: 'api');
    verify(
      (facadeSearch['data'] as List).length == 2,
      'HTTP client opens and carries session',
    );
    try {
      await facade.categories('api');
      throw StateError('unsupported category should fail');
    } on SourceException catch (error) {
      verify(error.code == 'UNSUPPORTED', 'HTTP client structured errors');
    }
    final listing = await client.get('/api/v1/sources');
    verify((listing.data['data'] as List).length == 6, 'source registry');
    verify(
      !(jsonEncode(listing.data).contains('searchApiConfig')),
      'public manifests omit rule credentials',
    );
    final unauthenticated = await client.get('/api/v1/sources/api/search?q=x');
    verify(unauthenticated.statusCode == 401, 'session required');
    final session = await client.post('/api/v1/sessions');
    client.options.headers['X-Kazumi-Session'] = session.data['id'];
    final postedSearch = await client.get(
      '/api/v1/sources/posted/search',
      queryParameters: {'q': '中 文'},
    );
    verify(
      postedSearch.statusCode == 200 &&
          seenBodies.last['q'] == '中 文' &&
          seenBodies.last['enabled'] == true,
      'POST JSON transport retains typed body',
    );
    final search = await client.get(
      '/api/v1/sources/api/search?q=测试&pageSize=1',
    );
    verify(
      search.statusCode == 200 && (search.data['data'] as List).length == 1,
      'local search page',
    );
    verify(
      search.data['pagination']['mode'] == 'local' &&
          search.data['pagination']['hasMore'] == true,
      'honest local pagination',
    );
    final contentId = search.data['data'][0]['id'];
    final detail = await client.get('/api/v1/sources/api/contents/$contentId');
    verify(
      detail.data['detailMode'] == 'reference',
      'reference detail does not invent metadata',
    );
    final lines = await client.get(
      '/api/v1/sources/api/contents/$contentId/lines',
    );
    verify(
      lines.data['data'][0]['episodes'][0]['title'] == 'SP',
      'episode label preserved',
    );
    final foreign = await client.get(
      '/api/v1/sources/xpath/contents/$contentId/lines',
    );
    verify(foreign.statusCode == 404, 'foreign ref rejected');
    final xpathSearch = await client.get('/api/v1/sources/xpath/search?q=动漫');
    final xpathLines = await client.get(
      '/api/v1/sources/xpath/contents/${xpathSearch.data['data'][0]['id']}/lines',
    );
    verify(
      xpathLines.data['data'][0]['episodes'][0]['title'] == 'OVA',
      'real XPath engine',
    );
    final upstream = await client.get(
      '/api/v1/sources/paged/search?q=x&page=2&pageSize=2',
    );
    verify(
      upstream.data['data'][0]['title'] == '第一季 2' &&
          upstream.data['pagination']['mode'] == 'upstream',
      'upstream placeholders',
    );
    verify(
      upstream.data['pagination']['total'] == 4 &&
          upstream.data['pagination']['hasMore'] == false,
      'upstream result mapping',
    );
    verify(
      (await client.get('/api/v1/sources/api/search?q=x&page=0')).statusCode ==
          400,
      'invalid paging',
    );
    verify(
      (await client.get('/api/v1/sources/api/categories')).statusCode == 422,
      'unsupported catalog explicit',
    );
    final directory = await client.get(
      '/api/v1/sources/xpath/contents?category=chinese',
    );
    verify(
      directory.data['data'][0]['classification']['region'] == 'CN',
      'directory classification evidence',
    );
    final aggregate = await client.get('/api/v1/search?q=x');
    verify(
      (aggregate.data['data'] as List).any(
        (r) => r['providerId'] == 'bad' && r['error'] != null,
      ),
      'aggregate partial errors',
    );
    final pagedAggregate = await client.get(
      '/api/v1/search?q=x&page=2&pageSize=1',
    );
    final pagedProvider = (pagedAggregate.data['data'] as List).firstWhere(
      (r) => r['providerId'] == 'paged',
    );
    verify(
      pagedProvider['data'][0]['title'] == '第一季 2' &&
          pagedProvider['pagination']['page'] == 2,
      'aggregate forwards pagination',
    );
    verify(
      (await client.get('/api/v1/search?q=x&page=0')).statusCode == 400,
      'aggregate validates pagination',
    );
    final health = await client.get('/api/v1/sources/api/health');
    verify(
      health.data['data']['search']['status'] == 'success' &&
          health.data['data']['resolve'] == null,
      'health separated by operation',
    );
    final resolutionInput = {
      'providerId': 'api',
      'contentId': contentId,
      'lineId': lines.data['data'][0]['id'],
      'episodeId': lines.data['data'][0]['episodes'][0]['id'],
    };
    final resolution = await client.post(
      '/api/v1/playback/resolutions',
      data: resolutionInput,
    );
    verify(resolution.statusCode == 202, 'asynchronous resolution accepted');
    final jobId = resolution.data['data']['id'];
    Map? ready;
    for (var i = 0; i < 50; i++) {
      final response = await client.get('/api/v1/playback/resolutions/$jobId');
      if (response.data['data']['status'] == 'ready') {
        ready = response.data['data'];
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    verify(
      ready != null && ready['result']['format'] == 'hls',
      'resolution ready',
    );
    final mediaPath = Uri.parse(ready!['result']['url'] as String).path;
    verify(
      mediaPath.startsWith('/api/v1/media/') &&
          !jsonEncode(ready).contains('headers='),
      'opaque media handle',
    );
    final playlist = await client.get<String>(
      mediaPath,
      options: Options(responseType: ResponseType.plain),
    );
    verify(
      playlist.data!.contains('/api/v1/media/') &&
          !playlist.data!.contains('cookie-secret'),
      'HLS child credentials hidden',
    );
    final challenge = await client.post(
      '/api/v1/challenges',
      data: {'providerId': 'xpath', 'keyword': 'x'},
    );
    final challengeId = challenge.data['data']['id'];
    for (var i = 0; i < 30; i++) {
      final response = await client.get('/api/v1/challenges/$challengeId');
      if (response.data['data']['status'] == 'ready') break;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await client.get('/api/v1/sources/xpath/search?q=x');
    verify(
      seenHeaders.last['cookie'] == 'verified=1' &&
          seenHeaders.last['user-agent'] == 'verified-agent',
      'verified context reused',
    );
    await client.get('/api/v1/sources/another-xpath/search?q=x');
    verify(
      seenHeaders.last['cookie'] == null &&
          seenHeaders.last['user-agent'] != 'verified-agent',
      'same-name providers keep separate verification context',
    );
    final other = await client.post('/api/v1/sessions');
    final oldSession = client.options.headers['X-Kazumi-Session'];
    client.options.headers['X-Kazumi-Session'] = other.data['id'];
    verify(
      (await client.get('/api/v1/playback/resolutions/$jobId')).statusCode ==
          404,
      'jobs isolated by session',
    );
    await client.get('/api/v1/sources/xpath/search?q=x');
    verify(seenHeaders.last['cookie'] == null, 'verification cookies isolated');
    client.options.headers['X-Kazumi-Session'] = oldSession;
    final cancelled = await client.post(
      '/api/v1/playback/resolutions',
      data: resolutionInput,
    );
    final cancelledId = cancelled.data['data']['id'];
    final cancel = await client.delete(
      '/api/v1/playback/resolutions/$cancelledId',
    );
    verify(
      cancel.data['data']['status'] == 'cancelled',
      'cancellation recorded',
    );
    await Future<void>.delayed(const Duration(milliseconds: 70));
    final stale = await client.get('/api/v1/playback/resolutions/$cancelledId');
    verify(
      stale.data['data']['status'] == 'cancelled' &&
          stale.data['data']['result'] == null,
      'cancelled result not published',
    );
    verify(
      (await client.post(
            '/api/v1/playback/resolutions',
            data: {'padding': 'x' * 33000},
          )).statusCode ==
          413,
      'payload bounded',
    );
    stdout.writeln(
      'PASS: $checks HTTP integration checks (actual Dart RuleEngine + localhost gateway fixtures)',
    );
  } finally {
    facade.dispose();
    client.close(force: true);
    await api.close();
    await fixture.close(force: true);
  }
}
