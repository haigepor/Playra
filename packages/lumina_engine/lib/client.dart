import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html;
import 'lumina_engine.dart';
import 'primitives.dart';
import 'response_backend.dart';
import 'response_context.dart';

typedef LuminaTrace = void Function(String stage, int microseconds);
Duration _remainingBudget() {
  if ((Zone.current[#luminaCancelled] as bool Function()?)?.call() == true) {
    throw const LuminaFailure('CANCELLED');
  }
  final budget = Zone.current[#luminaBudget] as (Stopwatch, Duration)?;
  final remaining = budget == null
      ? const Duration(seconds: 30)
      : budget.$2 - budget.$1.elapsed;
  if (remaining <= Duration.zero) throw TimeoutException('Lumina deadline');
  return remaining;
}

class LuminaFailure implements Exception {
  const LuminaFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

const maxResponseBytes = 2 * 1024 * 1024;

/// 解析器响应的 AES 密钥可能落后于 play 响应下发的 Lua 值（服务端轮换不同步，
/// 2026-11-02 实测有约四分钟错位窗口）。解码失败时按「当前 Lua → 历史值」回退。
const _resolverFallbackKeys = <(String, String)>[
  ('mjxhdyjgbyjaxcsx', 'quqgpueglvxrexar'),
  ('klwlqptyjkzlnkqp', 'dnprtsbqhiwccgqf'),
];

/// 单 worker 内复用连接；异步网络可并行，全部同步 C 调用天然串行。
class LuminaClient {
  LuminaClient(
    this.profile,
    String image,
    this.fingerprint, {
    this.trace,
    LuminaResponseBackend? responseBackend,
    bool strictResponseBackend = false,
  }) : engine = LuminaEngine(image, trace: trace),
       _responses = ResponseRouter(
         responseBackend,
         strict: strictResponseBackend,
       ),
       requestKey = RsaKey.publicDer(base64Decode(profile['_SERVER_PUB_B64'])),
       responseKey = RsaKey.privateDer(
         base64Decode(profile['_SERVER_PRIV_B64']),
       ) {
    // 将已验证的解析结果用于连接，避免检查后再次 DNS 解析进入本地地址。
    _http.findProxy = (_) => 'DIRECT';
    _http.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (proxyHost != null) throw const LuminaFailure('INVALID_MEDIA');
      final addresses = await InternetAddress.lookup(
        uri.host,
      ).timeout(const Duration(seconds: 5));
      if (addresses.isEmpty || addresses.any((a) => !_publicAddress(a)))
        throw const LuminaFailure('INVALID_MEDIA');
      return Socket.startConnect(addresses.first, uri.port);
    };
  }
  final Map<String, dynamic> profile;
  final String fingerprint;
  final LuminaEngine engine;
  final ResponseRouter _responses;
  final RsaKey requestKey, responseKey;
  final LuminaTrace? trace;
  final HttpClient _http = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..maxConnectionsPerHost = 4;
  final Random _rng = Random.secure();
  int _authTs = 0;
  String _authentication = '';
  T _timed<T>(String stage, T Function() action) {
    final watch = Stopwatch()..start();
    try {
      _remainingBudget();
      final result = action();
      _remainingBudget();
      return result;
    } finally {
      trace?.call(stage, watch.elapsedMicroseconds);
    }
  }

  Map<String, String> _headers() {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_authentication.isEmpty || now < _authTs || now - _authTs >= 90000) {
      _authTs = now;
      final s =
          '${profile['CODE_VERSION']}-$_authTs-Android-${profile['APP_VERSION']}-$fingerprint-${profile['CLIENT_CATEGORY']}';
      _authentication = _timed(
        'auth',
        () => cb64(
          engine.auth(
            hexBytes(profile['_AUTH_KEY']),
            hexBytes(profile['_AUTH_IV']),
            ascii.encode(cb64(ascii.encode(s))),
          ),
        ),
      );
    }
    return {
      'appid': '${profile['APP_ID']}',
      'ts': '$_authTs',
      'nonce': '${10000000 + _rng.nextInt(90000000)}',
      'tcs': '${profile['TCS']}',
      'x-version': '${profile['PROTOCOL_X_VERSION']}',
      'authentication': _authentication,
      'content-type': 'application/json; charset=utf-8',
      'user-agent': '${profile['USER_AGENT']}',
    };
  }

  Uint8List requestBody(Map<String, dynamic> params) {
    final key = Uint8List.fromList(List.generate(16, (_) => _rng.nextInt(256)));
    final data = utf8.encode(jsonEncode(params));
    final aligned = [...data, ...List.filled((-data.length) % 4, 32)];
    return Uint8List.fromList(
      ascii.encode(
        '${cb64(requestKey.encrypt(key))}.${cb64(engine.encrypt(key, pad(aligned)))}',
      ),
    );
  }

  Map<String, dynamic> openBody(Uint8List raw, {String path = '/'}) =>
      _timed('decrypt', () {
        final text = utf8.decode(raw);
        final envelope = splitEnvelope(text);
        final dynamic decoded;
        if (envelope != null) {
          final (p0, cipher) = envelope;
          if (p0.length < 256) throw const LuminaFailure('DECRYPT_ERROR');
          final result = _responses.decode(raw, path, _remainingBudget(), () {
            _remainingBudget();
            // 便携引擎的 Cb 生成器在 ~1944 块后会 abort 宿主进程（不可捕获），
            // 服务端分页上限保证正常响应远低于此；超限直接报错而不是杀掉 App。
            if (cipher.length ~/ 16 > LuminaEngine.maxBlocks)
              throw const LuminaFailure('RESPONSE_TOO_LARGE');
            final key = responseKey.decrypt(p0.sublist(0, 256));
            return engine.decrypt(key, cipher);
          });
          final route =
              Zone.current[#luminaResponseRoute] as Map<String, String>?;
          if (route != null) route['backend'] = result.backend;
          trace?.call('backend_${result.backend}', 0);
          if (result.fallback != null)
            trace?.call('fallback_${result.fallback}', 0);
          decoded = jsonDecode(utf8.decode(result.plain));
        } else {
          decoded = jsonDecode(text);
        }
        if (decoded is! Map<String, dynamic>)
          throw const LuminaFailure('PARSE_ERROR');
        return decoded;
      });
  Future<Uint8List> _fetch(
    String method,
    Uri uri,
    Map<String, String> headers, [
    List<int>? body,
  ]) async {
    validatePublicUri(uri.toString());
    final watch = Stopwatch()..start();
    HttpClientRequest? request;
    var expired = false;
    final deadline = Timer(_remainingBudget(), () {
      expired = true;
      request?.abort(TimeoutException('Lumina deadline'));
    });
    try {
      request = await _http
          .openUrl(method, uri)
          .timeout(const Duration(seconds: 8));
      _remainingBudget();
      request.followRedirects = false;
      headers.forEach((k, v) => request!.headers.set(k, v));
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != 200) {
        request.abort();
        throw const LuminaFailure('UPSTREAM_HTTP_ERROR');
      }
      if (response.contentLength > maxResponseBytes) {
        request.abort();
        throw const LuminaFailure('RESPONSE_TOO_LARGE');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          request.abort();
          throw const LuminaFailure('RESPONSE_TOO_LARGE');
        }
        bytes.add(chunk);
      }
      return bytes.takeBytes();
    } catch (_) {
      request?.abort();
      if (expired) throw TimeoutException('Lumina deadline');
      rethrow;
    } finally {
      deadline.cancel();
      trace?.call('http', watch.elapsedMicroseconds);
    }
  }

  Future<Map<String, dynamic>> _api(
    String path, {
    Map<String, dynamic> query = const {},
    bool post = false,
  }) async {
    final uri = Uri(
      scheme: 'http',
      host: profile['API_HOST'],
      port: profile['API_PORT'] as int,
      path: path,
      queryParameters: query.isEmpty
          ? null
          : query.map((k, v) => MapEntry(k, '$v')),
    );
    return openBody(
      await _fetch(
        post ? 'POST' : 'GET',
        uri,
        _headers(),
        post ? _timed('request_encrypt', () => requestBody({})) : null,
      ),
      path: luminaResponsePath(uri),
    );
  }

  dynamic _data(Map<String, dynamic> result) {
    if (result['code'] != 20000) throw const LuminaFailure('BUSINESS_REJECTED');
    return result['data'];
  }

  Future<Map<String, dynamic>> call(
    String operation,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
    bool Function()? isCancelled,
  }) => runZoned(
    () => _call(operation, payload),
    zoneValues: {
      #luminaBudget: (Stopwatch()..start(), timeout),
      #luminaCancelled: isCancelled,
      #luminaResponseRoute: <String, String>{},
    },
  );
  Future<Map<String, dynamic>> _call(
    String operation,
    Map<String, dynamic> payload,
  ) async {
    final p = validatePayload(operation, payload);
    try {
      _remainingBudget();
      final dynamic data;
      switch (operation) {
        case 'config':
          _data(await _api('/app/config'));
          data = {'available': true};
        case 'channels':
          data = normalize(
            operation,
            _data(await _api('/app/channel', query: {'top-level': 'true'})),
            p,
          );
        case 'banners':
          data = normalize(
            operation,
            _data(await _api('/app/banners/${p['channelId']}')),
            p,
          );
        case 'catalog':
          data = normalize(
            operation,
            _data(
              await _api(
                '/app/video/list',
                query: {
                  'channel': p['channelId'],
                  'sort': p['sort'],
                  'limit': p['pageSize'],
                  'page': p['pageIndex'],
                },
              ),
            ),
            p,
          );
        case 'search':
          data = normalize(
            operation,
            _data(
              await _api(
                '/app/video/search',
                query: {
                  'key': p['keyword'],
                  'limit': p['pageSize'],
                  'page': p['pageIndex'],
                },
              ),
            ),
            p,
          );
        case 'detail':
          data = normalize(
            operation,
            _data(await _api('/app/video/detail', query: {'id': p['videoId']})),
            p,
          );
        case 'play':
          data = await _play(p);
        default:
          throw const LuminaFailure('UNSUPPORTED');
      }
      _remainingBudget();
      return {
        'data': data,
        'meta': {
          'providerId': 'lumina',
          'operation': operation,
          'backend': 'dart-c',
          'engine': engine.version,
          'responseBackend':
              (Zone.current[#luminaResponseRoute]
                  as Map<String, String>?)?['backend'] ??
              'plaintext',
        },
      };
    } on ResponseBackendFailure catch (error) {
      throw LuminaFailure(error.code);
    } on LuminaFailure {
      rethrow;
    } on TimeoutException {
      throw const LuminaFailure('TIMEOUT');
    } on SocketException {
      throw const LuminaFailure('UPSTREAM_UNAVAILABLE');
    } on HttpException {
      throw const LuminaFailure('UPSTREAM_UNAVAILABLE');
    } on FormatException {
      throw const LuminaFailure('PARSE_ERROR');
    } on StateError {
      throw const LuminaFailure('ENGINE_ERROR');
    } catch (_) {
      throw const LuminaFailure('PARSE_ERROR');
    }
  }

  /// 播放链路两种 source：
  /// - **直链型**（电影/单片）：url 本身就是 CDN 地址，原样返回，不碰解析器；
  /// - **不透明串型**（`a|b|c|d`，剧集）：play → Lua 签名 → 解析器链。
  ///
  /// 两种瞬态按同参数重试一次：`510423 播放遇到问题`（服务端状态），
  /// 以及解析器密钥轮换造成的解码失败（见 [_resolverFallbackKeys]）。
  Future<Map<String, dynamic>> _play(Map<String, dynamic> p) async {
    Object? failure;
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        _remainingBudget();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      _remainingBudget();
      final reply = await _api(
        '/app/video/play',
        query: {'id': p['videoId'], 'play': p['playFormat'], 'part': p['part']},
        post: true,
      );
      if (reply['code'] != 20000) {
        failure = const LuminaFailure('BUSINESS_REJECTED');
        if (reply['code'] == 510423) continue;
        throw failure;
      }
      dynamic entries = reply['data'];
      if (entries is Map) entries = entries['data'];
      if (entries is! List || entries.isEmpty)
        return {'status': 'unavailable', 'error': 'NO_PLAYBACK_SOURCE'};
      final entry = entries.first;
      if (entry is! Map) throw const LuminaFailure('PARSE_ERROR');
      final source = entry['url'];
      if (source is! String || source.isEmpty || source.length > 16384)
        throw const LuminaFailure('PARSE_ERROR');
      if (source.startsWith('http')) {
        final media = _directMedia(entry, source);
        return {
          'status': 'ready',
          'kind': 'direct',
          'media': media,
          'medias': [media],
        };
      }
      try {
        return {...await _resolveSource(p, entry, source), 'kind': 'resolver'};
      } catch (error) {
        failure = error;
      }
    }
    throw failure is LuminaFailure
        ? failure
        : const LuminaFailure('RESOLVER_PARSE_ERROR');
  }

  Map<String, dynamic> _directMedia(Map entry, String source) {
    final uri = validatePublicUri(source);
    return {
      'url': source,
      'headers': _streamHeaders(uri),
      'name': '${entry['play_zh'] ?? ''} ${entry['part'] ?? ''}'.trim(),
      'format': uri.path.endsWith('.m3u8') ? 'hls' : 'mp4',
    };
  }

  Future<Map<String, dynamic>> _resolveSource(
    Map<String, dynamic> p,
    Map entry,
    String source,
  ) async {
    final script = entry['parse'] as String? ?? '';
    String param(String field, String fallback) =>
        RegExp('$field\\s*=\\s*"([^"]+)"').firstMatch(script)?.group(1) ??
        fallback;
    final urls = RegExp(
      r'''https?://[^\s"'\]]+''',
    ).allMatches(script).map((m) => m.group(0)!);
    final parser =
        urls
            .where(
              (s) =>
                  s.replaceFirst(RegExp(r'/+$'), '').endsWith('=') ||
                  s.contains('.php?url='),
            )
            .firstOrNull ??
        profile['PARSER_URL'] as String;
    final salt = param(
          'salt',
          // 新脚本不再下发 salt 字段，改成 sign() 里的字面量：
          //   return utils.md5(data .. "kvdenozcjy" .. ts)
          RegExp(r'\.\.\s*"([^"]+)"\s*\.\.').firstMatch(script)?.group(1) ??
              profile['PARSER_SALT'],
        ),
        aesKey = param('aes_key', profile['PARSER_AES_KEY']),
        iv = param('aes_iv', profile['PARSER_AES_IV']);
    final ts = DateTime.now().millisecondsSinceEpoch;
    String digest(String value) => md5.convert(utf8.encode(value)).toString();
    final raw = await _fetch('GET', Uri.parse('$parser$source&t=$ts'), {
      'x-time': '$ts',
      'x-form': profile['PARSER_PLATFORM'],
      'user-agent': profile['USER_AGENT'],
      'x-sign1': digest('${profile['APP_VERSION']}$salt$ts'),
      'x-sign2': digest('$source$salt$ts'),
    });
    final parsed = _timed(
      'resolver_parse',
      () => parseResolver(
        utf8.decode(raw),
        aesKey,
        iv,
        fallbacks: _resolverFallbackKeys,
      ),
    );
    final links = directLinks(parsed);
    return links.isEmpty
        ? {'status': 'unavailable', 'error': 'NO_DIRECT_LINK'}
        : {'status': 'ready', 'media': links.first, 'medias': links};
  }

  void close() {
    engine.clearCalibrationCache();
    _http.close(force: true);
  }
}

Map<String, dynamic> validatePayload(
  String operation,
  Map<String, dynamic> payload,
) {
  final allowed = switch (operation) {
    'config' || 'channels' => <String>{},
    'banners' => {'channelId'},
    'catalog' => {'channelId', 'pageIndex', 'pageSize', 'sort'},
    'search' => {'keyword', 'pageIndex', 'pageSize'},
    'detail' => {'videoId'},
    'play' => {'videoId', 'playFormat', 'part'},
    _ => throw const LuminaFailure('UNSUPPORTED'),
  };
  void require(bool condition) {
    if (!condition) throw const LuminaFailure('INVALID_ARGUMENT');
  }

  require(payload.keys.every(allowed.contains));
  final p = Map<String, dynamic>.from(payload);
  for (final key in ['channelId', 'videoId']) {
    if (allowed.contains(key))
      require(p[key] is String && RegExp(r'^\d{1,64}$').hasMatch(p[key]));
  }
  if (operation == 'search') {
    require(
      p['keyword'] is String &&
          (p['keyword'] as String).trim().isNotEmpty &&
          (p['keyword'] as String).length <= 300,
    );
    p['keyword'] = (p['keyword'] as String).trim();
  }
  if (operation == 'search' || operation == 'catalog') {
    p.putIfAbsent('pageIndex', () => 1);
    p.putIfAbsent('pageSize', () => operation == 'catalog' ? 24 : 12);
  }
  for (final pair in [('pageIndex', 1000000), ('pageSize', 100)]) {
    if (p.containsKey(pair.$1))
      require(p[pair.$1] is int && p[pair.$1] >= 1 && p[pair.$1] <= pair.$2);
  }
  if (operation == 'catalog') {
    p.putIfAbsent('sort', () => 'weight');
    require(
      p['sort'] is String &&
          RegExp(r'^[\w\-\u4e00-\u9fff]{1,80}$').hasMatch(p['sort']),
    );
  }
  if (operation == 'play') {
    require(
      p['playFormat'] is String &&
          RegExp(r'^[A-Za-z0-9_+.\-]{1,64}$').hasMatch(p['playFormat']),
    );
    require(
      p['part'] is String &&
          (p['part'] as String).trim().isNotEmpty &&
          (p['part'] as String).length <= 512 &&
          !(p['part'] as String).runes.any((c) => c < 32),
    );
  }
  return p;
}

Uri validatePublicUri(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.port < 1 ||
      uri.port > 65535 ||
      url.length > 16384 ||
      url.runes.any((c) => c < 32))
    throw const LuminaFailure('INVALID_MEDIA');
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  final address = InternetAddress.tryParse(host);
  if (host == 'localhost' ||
      host.endsWith('.localhost') ||
      host.endsWith('.local') ||
      host.endsWith('.internal') ||
      (address != null && !_publicAddress(address)))
    throw const LuminaFailure('INVALID_MEDIA');
  return uri;
}

bool _publicAddress(InternetAddress address) {
  final b = address.rawAddress;
  if (address.isLoopback || address.isLinkLocal || address.isMulticast)
    return false;
  if (b.length == 4)
    return b[0] != 0 &&
        b[0] != 10 &&
        b[0] != 127 &&
        !(b[0] == 172 && b[1] >= 16 && b[1] <= 31) &&
        !(b[0] == 192 && b[1] == 168) &&
        !(b[0] == 169 && b[1] == 254) &&
        !(b[0] == 100 && b[1] >= 64 && b[1] <= 127) &&
        b[0] < 224;
  return b.any((v) => v != 0) &&
      b[0] & 254 != 252 &&
      !(b.take(10).every((v) => v == 0) && b[10] == 255 && b[11] == 255);
}

String _text(dynamic value, [int max = 1000]) => value is String || value is num
    ? value.toString().substring(0, min(max, value.toString().length))
    : '';
String _id(dynamic value) =>
    RegExp(r'^\d{1,64}$').hasMatch('$value') ? '$value' : '';
int? _number(dynamic value) {
  final n = int.tryParse('$value');
  return n != null && n >= 0 && n <= 10000000 ? n : null;
}

String _cover(dynamic value) {
  final s = _text(value, 8192);
  try {
    validatePublicUri(s);
    return s;
  } catch (_) {
    return '';
  }
}

Map<String, dynamic> _video(dynamic row) {
  if (row is! Map || _id(row['id']).isEmpty)
    throw const LuminaFailure('PARSE_ERROR');
  return {
    'id': _id(row['id']),
    'title': _text(row['title']).isEmpty
        ? _text(row['name'])
        : _text(row['title']),
    'name': _text(row['name']),
    'cover': _cover(row['pic'] ?? row['cover']),
    'summary':
        html
            .parseFragment(
              _text(row['content'], 100000).replaceAll(RegExp(r'<[^>]*>'), ''),
            )
            .text ??
        '',
    'year': _text(row['year'], 40),
    'area': _text(row['area'], 200),
    'categoryId': _id(row['cid']),
    'isEnd': [1, '1', true].contains(row['isend']),
    if (_number(row['continu']) case final n?) 'updatedTo': n,
    if (_number(row['total']) case final n?) 'totalEpisodes': n,
  };
}

Map<String, dynamic> normalize(
  String operation,
  dynamic data,
  Map<String, dynamic> p,
) {
  if (operation == 'catalog' || operation == 'search') {
    if (data is! Map ||
        data['items'] is! List ||
        (data['items'] as List).length > 100)
      throw const LuminaFailure('PARSE_ERROR');
    return {
      'videos': [for (final row in data['items']) _video(row)],
      'pageInfo': {
        'pageIndex': p['pageIndex'],
        'pageSize': p['pageSize'],
        'total': _number(data['total']) ?? 0,
      },
    };
  }
  if (operation == 'detail') {
    final video = _video(data);
    final parts = data['parts'] ?? [];
    if (parts is! List || parts.length > 100)
      throw const LuminaFailure('PARSE_ERROR');
    final roads = <Map<String, dynamic>>[];
    for (final part in parts) {
      if (part is! Map ||
          part['part'] is! List ||
          (part['part'] as List).length > 10000 ||
          part['play'] is! String ||
          !RegExp(r'^[A-Za-z0-9_+.\-]{1,64}$').hasMatch(part['play']))
        throw const LuminaFailure('PARSE_ERROR');
      final episodes = <Map<String, dynamic>>[];
      for (final name in part['part']) {
        if (name is! String ||
            name.trim().isEmpty ||
            name.length > 512 ||
            name.runes.any((c) => c < 32))
          throw const LuminaFailure('PARSE_ERROR');
        episodes.add({
          'part': name,
          'name': name,
          'index': episodes.length + 1,
        });
      }
      roads.add({
        'play': part['play'],
        'name': _text(part['play_zh']).isEmpty
            ? part['play']
            : _text(part['play_zh']),
        'oid': _text(part['oid'], 64),
        'episodes': episodes,
      });
    }
    return {'video': video, 'parts': roads};
  }
  if (data is! List || data.length > 200)
    throw const LuminaFailure('PARSE_ERROR');
  if (operation == 'channels')
    return {
      'channels': [
        for (final row in data)
          if (row is Map && _id(row['id']).isNotEmpty)
            {
              'id': _id(row['id']),
              'name': _text(row['name']),
              'types': [
                for (final t in (row['types'] as List? ?? []).take(100))
                  if (t is String) _text(t, 80),
              ],
            },
      ],
    };
  return {
    'banners': [
      for (final row in data)
        if (row is Map)
          {
            'id': _id(row['id']),
            'videoId': _id(row['vid'] ?? row['video_id'] ?? row['videoId']),
            'title': _text(row['title'] ?? row['name'] ?? row['vname']),
            'cover': _cover(
              row['pic'] ?? row['image'] ?? row['img'] ?? row['cover'],
            ),
          },
    ],
  };
}

Map<String, dynamic> parseResolver(
  String text,
  String key,
  String iv, {
  List<(String, String)> fallbacks = const [],
}) {
  final s = text.trim();
  try {
    final j = jsonDecode(s);
    if (j is Map<String, dynamic>) return j;
  } catch (_) {
    /* encrypted candidate */
  }
  final candidates = <List<int>>[];
  if (s.length % 32 == 0 && RegExp(r'^[0-9a-fA-F]+$').hasMatch(s))
    candidates.add(hexBytes(s));
  // 标准表优先：解析器实际给的就是标准 base64；自定义表对同一串也能「成功」
  // 解出等长垃圾，只是解不出明文，放后面照样覆盖。
  for (final decode in [
    (String v) => base64Decode(base64.normalize(v)),
    uncb64,
  ]) {
    try {
      candidates.add(decode(s));
    } catch (_) {
      /* next encoding */
    }
  }
  final keys = <(String, String)>[(key, iv)];
  for (final pair in fallbacks) {
    if (!keys.contains(pair)) keys.add(pair);
  }
  for (final (candidateKey, candidateIv) in keys) {
    for (final bytes in candidates) {
      try {
        final j = jsonDecode(
          utf8.decode(
            Aes128(
              utf8.encode(candidateKey),
            ).cbcDecrypt(bytes, utf8.encode(candidateIv)),
          ),
        );
        if (j is Map<String, dynamic>) return j;
      } catch (_) {
        /* next key or encoding */
      }
    }
  }
  throw const LuminaFailure('RESOLVER_PARSE_ERROR');
}

List<Map<String, dynamic>> directLinks(Map<String, dynamic> parsed) {
  final dynamic rows = parsed['data'] is Map
      ? parsed['data']['playAddr']
      : null;
  final candidates = rows is List && rows.isNotEmpty
      ? rows
      : parsed['url'] is String
      ? [
          {
            'm3u8FileDomain': '',
            'addr': parsed['url'],
            'desc': parsed['type'] ?? 'mp4',
            'format': parsed['type'],
          },
        ]
      : [];
  if (candidates.length > 20) throw const LuminaFailure('RESPONSE_TOO_LARGE');
  return [for (final row in candidates) _media(row)];
}

Map<String, dynamic> _media(dynamic row) {
  if (row is! Map) throw const LuminaFailure('INVALID_MEDIA');
  final url = '${row['m3u8FileDomain'] ?? ''}${row['addr'] ?? ''}',
      uri = validatePublicUri(url);
  final format = _text(row['format']);
  return {
    'url': url,
    'headers': _streamHeaders(uri),
    'name': '${row['desc'] ?? ''} ${row['title'] ?? ''}'.trim(),
    'format': ['mp4', 'm3u8', 'hls'].contains(format)
        ? format
        : uri.path.endsWith('.m3u8')
        ? 'hls'
        : 'auto',
    if (row['vcodec'] != null) 'vcodec': _text(row['vcodec'], 40),
  };
}

/// 播放器请求头：与 referer 默认取地址本身；已知 CDN 按站点要求换 referer。
Map<String, String> _streamHeaders(Uri uri) {
  var referer = uri.toString();
  for (final entry in {
    'aliyuncs.com': 'https://www.piccopilot.com',
    'toutiaovod.com': '',
    'kwimgs.com': 'https://www.kuaishou.com',
    'dcarvod.com': 'https://www.dongchedi.com',
    'douyinvod.com': 'https://www.douyin.com',
  }.entries) {
    if (uri.host.endsWith(entry.key)) {
      referer = entry.value;
      break;
    }
  }
  return {'User-Agent': '', 'Referer': referer};
}
