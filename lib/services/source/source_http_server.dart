import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:kazumi/services/plugin/rule_engine.dart';
import 'source_directory.dart';
import 'source_gateway.dart';
import 'source_models.dart';
import 'source_service.dart';

String _handle() => base64Url
    .encode(List.generate(24, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');

class _ApiSession {
  _ApiSession(this.gateway, this.service, this.directory);
  final SourceGateway gateway;
  final SourceService service;
  final SourceDirectoryRegistry directory;
  DateTime touchedAt = DateTime.now();
  final Map<String, SourceContent> contents = {};
  final Map<String, List<SourceLine>> lines = {};
  final Map<String, _BrowserJob> jobs = {};
  void remember(Iterable<SourceContent> items) {
    for (final item in items) {
      contents[item.ref.id] = item;
    }
    while (contents.length > 2000) {
      final id = contents.keys.first;
      contents.remove(id);
      lines.remove(id);
    }
  }
}

class _BrowserJob {
  _BrowserJob(this.id, this.providerId, this.context, this.kind);
  final String id, providerId, kind;
  final SourceContext context;
  final createdAt = DateTime.now();
  String status = 'pending';
  String? backendId, targetUrl;
  Map<String, dynamic>? result;
  SourceException? error;
  Future<void>? polling;
  Map<String, dynamic> toJson() => {
    'id': id,
    'providerId': providerId,
    'kind': kind,
    'status': status,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (result != null) 'result': result,
    if (error != null) 'error': error!.toJson(),
  };
}

class SourceHttpServer {
  SourceHttpServer({
    required List<SourceDefinition> sources,
    required this.gateway,
    this.serviceFactory,
    this.directoryFactory,
  }) : sources = {for (final source in sources) source.manifest.id: source};
  final Map<String, SourceDefinition> sources;
  final SourceGateway gateway;
  // 测试仅注入传输边界；规则解析和 HTTP 路由使用实际实现。
  final SourceService Function(SourceGateway gateway)? serviceFactory;
  final SourceDirectoryRegistry Function(
    SourceGateway gateway,
    SourceService service,
  )?
  directoryFactory;
  final Map<String, _ApiSession> _sessions = {};
  final Map<
    String,
    ({String url, Map<String, String> headers, DateTime expiresAt})
  >
  _media = {};
  HttpServer? _server;
  Timer? _expiry;
  int _active = 0;
  Future<int> start({int port = 8940}) async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _server!.listen((request) => unawaited(_handleRequest(request)));
    _expiry = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(_prune()),
    );
    return _server!.port;
  }

  Future<void> _prune() async {
    final now = DateTime.now();
    _media.removeWhere((_, ticket) => ticket.expiresAt.isBefore(now));
    for (final entry in _sessions.entries.toList()) {
      for (final job in entry.value.jobs.values.toList()) {
        if (now.difference(job.createdAt) > const Duration(minutes: 2)) {
          await _cancel(entry.value, job);
          entry.value.jobs.remove(job.id);
        }
      }
      if (now.difference(entry.value.touchedAt) > const Duration(minutes: 30)) {
        for (final job in entry.value.jobs.values) {
          await _cancel(entry.value, job);
        }
        _sessions.remove(entry.key);
      }
    }
  }

  Future<void> close() async {
    _expiry?.cancel();
    for (final session in _sessions.values) {
      for (final job in session.jobs.values) {
        await _cancel(session, job);
      }
    }
    await _server?.close(force: true);
    gateway.dispose();
  }

  _ApiSession _session(HttpRequest request) {
    final id = request.headers.value('x-kazumi-session');
    final session = _sessions[id];
    if (session == null) {
      throw const SourceException('SESSION_REQUIRED', '请先创建来源会话');
    }
    if (DateTime.now().difference(session.touchedAt) >
        const Duration(minutes: 30)) {
      throw const SourceException('SESSION_REQUIRED', '来源会话已过期');
    }
    session.touchedAt = DateTime.now();
    return session;
  }

  SourceDefinition _source(String id) =>
      sources[id] ?? (throw const SourceException('NOT_FOUND', '来源不存在'));
  SourceContent _content(_ApiSession session, String id, String providerId) {
    final item = session.contents[id];
    if (item == null || item.ref.providerId != providerId) {
      throw const SourceException('NOT_FOUND', '条目引用不存在，请在当前会话重新搜索');
    }
    return item;
  }

  int _number(HttpRequest request, String key, int defaultValue) {
    final raw = request.uri.queryParameters[key];
    if (raw == null) return defaultValue;
    final value = int.tryParse(raw);
    if (value == null) {
      throw const SourceException('INVALID_ARGUMENT', '分页参数必须是整数');
    }
    return value;
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final bytes = <int>[];
    var tooLarge = false;
    await for (final chunk in request) {
      if (bytes.length + chunk.length > 32768) tooLarge = true;
      if (!tooLarge) bytes.addAll(chunk);
    }
    // 读完请求流再回应，避免取消 HttpRequest 订阅导致连接先于 413 响应关闭。
    if (tooLarge) throw const SourceException('PAYLOAD_TOO_LARGE', '请求体过大');
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) {
      throw const SourceException('INVALID_ARGUMENT', '请求体必须是 JSON 对象');
    }
    return data;
  }

  Map<String, dynamic> _page(SourcePage<SourceContent> page) => {
    'data': page.items.map((e) => e.toJson()).toList(),
    'pagination': page.pagination.toJson(),
  };

  String _mediaUrl(String url, Map<String, String> headers) {
    _media.removeWhere(
      (_, ticket) => ticket.expiresAt.isBefore(DateTime.now()),
    );
    if (_media.length >= 4096) throw const SourceException('BUSY', '媒体引用过多');
    final token = _handle();
    _media[token] = (
      url: url,
      headers: headers,
      expiresAt: DateTime.now().add(const Duration(hours: 2)),
    );
    return gateway.base.resolve('/api/v1/media/$token').toString();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    var acquired = false;
    try {
      final host = Uri.tryParse(
        'http://${request.headers.value('host') ?? ''}',
      )?.host;
      if (!['127.0.0.1', 'localhost'].contains(host)) {
        throw const SourceException('FORBIDDEN', '仅接受本机 Host');
      }
      final origin = request.headers.value('origin');
      if (origin != null) {
        final uri = Uri.tryParse(origin);
        if (uri == null || !['127.0.0.1', 'localhost'].contains(uri.host)) {
          throw const SourceException('FORBIDDEN', '仅接受本机或同源请求');
        }
      }
      if (_active >= 12) throw const SourceException('BUSY', '请求过多，请稍后重试');
      _active++;
      acquired = true;
      final path = request.uri.pathSegments;
      if (path.length < 3 || path[0] != 'api' || path[1] != 'v1') {
        throw const SourceException('NOT_FOUND', '接口不存在');
      }
      final method = request.method;
      if (path.length == 4 &&
          path[2] == 'media' &&
          ['GET', 'HEAD'].contains(method)) {
        final ticket = _media[path[3]];
        if (ticket == null || ticket.expiresAt.isBefore(DateTime.now())) {
          throw const SourceException('NOT_FOUND', '媒体引用不存在或已过期');
        }
        final response = await gateway.client.request<ResponseBody>(
          gateway.base
              .resolve('/api/proxy')
              .replace(queryParameters: {'url': ticket.url})
              .toString(),
          options: Options(
            method: method,
            responseType: ResponseType.stream,
            headers: {
              'X-Kazumi-Request': '1',
              'X-Kazumi-Headers': base64Url.encode(
                utf8.encode(
                  jsonEncode({
                    ...ticket.headers,
                    if (request.headers.value('range') != null)
                      'range': request.headers.value('range'),
                  }),
                ),
              ),
            },
          ),
        );
        request.response.statusCode = response.statusCode ?? 200;
        final isHls =
            (response.headers.value('content-type') ?? '').contains(
              'mpegurl',
            ) ||
            Uri.parse(ticket.url).path.endsWith('.m3u8');
        for (final name in [
          'content-type',
          'content-range',
          'accept-ranges',
          'content-length',
        ]) {
          if (isHls && name == 'content-length') continue;
          final value = response.headers.value(name);
          if (value != null) request.response.headers.set(name, value);
        }
        if (isHls && method == 'GET') {
          final bytes = <int>[];
          await for (final chunk in response.data!.stream) {
            bytes.addAll(chunk);
            if (bytes.length > 4 * 1024 * 1024) {
              throw const SourceException('PAYLOAD_TOO_LARGE', '媒体列表过大');
            }
          }
          String rewrite(String raw) {
            final proxied = gateway.base.resolve(raw);
            final target =
                proxied.path == '/api/proxy' &&
                    proxied.queryParameters['url'] != null
                ? proxied.queryParameters['url']!
                : Uri.parse(ticket.url).resolve(raw).toString();
            final headers = Map<String, String>.from(ticket.headers);
            if (Uri.parse(target).host != Uri.parse(ticket.url).host) {
              headers.remove('cookie');
              headers.remove('authorization');
            }
            return _mediaUrl(target, headers);
          }

          final playlist = utf8
              .decode(bytes)
              .split('\n')
              .map((line) {
                if (line.trim().isNotEmpty && !line.startsWith('#')) {
                  return rewrite(line.trim());
                }
                return line.replaceAllMapped(
                  RegExp(r'URI="([^"]+)"'),
                  (m) => 'URI="${rewrite(m[1]!)}"',
                );
              })
              .join('\n');
          request.response.write(playlist);
        } else {
          await request.response.addStream(response.data!.stream);
        }
        return;
      }
      Map<String, dynamic> output;
      if (path.length == 3 && path[2] == 'health' && method == 'GET') {
        output = {'status': 'ok', 'apiVersion': '1', 'sources': sources.length};
      } else if (path.length == 3 &&
          path[2] == 'sessions' &&
          method == 'POST') {
        if (request.contentLength != 0) await _body(request);
        if (_sessions.length >= 64) throw const SourceException('BUSY', '会话过多');
        final id = _handle();
        final transport = gateway.scoped(id);
        for (final source in sources.values) {
          transport.bindSource(source.execution, source.manifest.id);
        }
        final service =
            serviceFactory?.call(transport) ??
            SourceService(engine: gatewayEngine(transport));
        _sessions[id] = _ApiSession(
          transport,
          service,
          directoryFactory?.call(transport, service) ??
              SourceDirectoryRegistry(executor: transport, service: service),
        );
        request.response.statusCode = 201;
        output = {'id': id, 'expiresInSeconds': 1800};
      } else if (path.length == 3 && path[2] == 'sources' && method == 'GET') {
        output = {
          'data': sources.values.map((s) => s.manifest.toJson()).toList(),
        };
      } else if (path[2] == 'sources' && path.length >= 4) {
        final source = _source(path[3]);
        if (method != 'GET') {
          throw const SourceException('METHOD_NOT_ALLOWED', '接口仅支持 GET');
        }
        if (path.length == 4) {
          output = {'data': source.manifest.toJson()};
        } else {
          final session = _session(request);
          final ctx = SourceContext(
            sessionId: request.headers.value('x-kazumi-session')!,
          );
          final page = _number(request, 'page', 1),
              size = _number(request, 'pageSize', 20);
          SourcePage.validate(page, size);
          if (path.length == 5 && path[4] == 'health') {
            output = {'data': session.service.healthJson(source.manifest.id)};
          } else if (path.length == 5 && path[4] == 'categories') {
            output = {'data': session.directory.categories(source)};
          } else if (path.length == 5 && path[4] == 'search') {
            final result = await session.service.search(
              source,
              request.uri.queryParameters['q'] ?? '',
              context: ctx,
              page: page,
              pageSize: size,
            );
            session.remember(result.items);
            output = _page(result);
          } else if (path.length == 5 && path[4] == 'contents') {
            final category = request.uri.queryParameters['category'] ?? 'all';
            if (!session.directory
                .categories(source)
                .any((c) => c['id'] == category)) {
              throw const SourceException('INVALID_ARGUMENT', '分类不存在');
            }
            final result = await session.directory.load(source, context: ctx);
            final unique = <String, SourceContent>{};
            for (final item in result.items) {
              if (category == 'all' ||
                  item.classification.rawCategory == category) {
                unique[item.ref.id] = item;
              }
            }
            final paged = SourcePage.local(
              unique.values.toList(),
              page: page,
              pageSize: size,
            );
            session.remember(paged.items);
            output = {..._page(paged), 'warnings': result.failures};
          } else if (path.length >= 6 && path[4] == 'contents') {
            final item = _content(session, path[5], source.manifest.id);
            if (path.length == 6) {
              output = {'data': item.toJson(), 'detailMode': 'reference'};
            } else if (path.length == 7 && path[6] == 'lines') {
              final lines = await session.service.lines(
                source,
                item.ref,
                context: ctx,
              );
              session.lines[item.ref.id] = lines;
              output = {'data': lines.map((l) => l.toJson()).toList()};
            } else {
              throw const SourceException('NOT_FOUND', '接口不存在');
            }
          } else {
            throw const SourceException('NOT_FOUND', '接口不存在');
          }
        }
      } else if (path.length == 3 && path[2] == 'search' && method == 'GET') {
        final session = _session(request);
        final keyword = request.uri.queryParameters['q'] ?? '';
        if (keyword.trim().isEmpty) {
          throw const SourceException('INVALID_ARGUMENT', '搜索词不能为空');
        }
        final requestedPage = _number(request, 'page', 1);
        final pageSize = _number(request, 'pageSize', 20);
        SourcePage.validate(requestedPage, pageSize);
        // 每个来源结果都经过 session 服务，同一会话内可继续调用剧集接口。
        final data = <Map<String, dynamic>>[];
        var next = 0;
        final providers = sources.values.toList();
        Future<void> worker() async {
          while (next < providers.length) {
            final source = providers[next++];
            try {
              final page = await session.service.search(
                source,
                keyword,
                page: requestedPage,
                pageSize: pageSize,
                context: SourceContext(
                  providerId: source.manifest.id,
                  sessionId: request.headers.value('x-kazumi-session')!,
                ),
              );
              session.remember(page.items);
              data.add({'providerId': source.manifest.id, ..._page(page)});
            } on SourceException catch (error) {
              data.add({
                'providerId': source.manifest.id,
                'error': error.toJson(),
              });
            }
          }
        }

        await Future.wait(
          List.generate(providers.length.clamp(0, 4), (_) => worker()),
        );
        output = {'data': data};
      } else if (path[2] == 'playback' || path[2] == 'challenges') {
        output = await _browserRoute(request, path);
      } else {
        throw const SourceException('NOT_FOUND', '接口不存在');
      }
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set('Cache-Control', 'no-store');
      request.response.write(jsonEncode(output));
    } catch (error) {
      final mapped = error is SourceException
          ? error
          : error is FormatException || error is TypeError
          ? const SourceException('INVALID_ARGUMENT', '请求数据格式无效')
          : const SourceException('INTERNAL_ERROR', '服务请求失败');
      request.response.statusCode = switch (mapped.code) {
        'SESSION_REQUIRED' => 401,
        'FORBIDDEN' => 403,
        'NOT_FOUND' => 404,
        'METHOD_NOT_ALLOWED' => 405,
        'CHALLENGE_REQUIRED' => 409,
        'PAYLOAD_TOO_LARGE' => 413,
        'BUSY' => 429,
        'UNSUPPORTED' => 422,
        'SOURCE_ERROR' || 'PARSE_ERROR' => 502,
        'TIMEOUT' => 504,
        'INVALID_ARGUMENT' || 'INVALID_REFERENCE' => 400,
        _ => 500,
      };
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'error': mapped.toJson()}));
    } finally {
      if (acquired) _active--;
      await request.response.close();
    }
  }

  Future<Map<String, dynamic>> _browserRoute(
    HttpRequest request,
    List<String> path,
  ) async {
    final session = _session(request);
    final resolution = path[2] == 'playback';
    final baseLength = resolution ? 4 : 3;
    if (resolution && (path.length < 4 || path[3] != 'resolutions')) {
      throw const SourceException('NOT_FOUND', '接口不存在');
    }
    if (path.length == baseLength && request.method == 'POST') {
      final data = await _body(request);
      final source = _source(data['providerId'] as String? ?? '');
      if (session.jobs.length >= 8) {
        throw const SourceException('BUSY', '会话任务过多');
      }
      final context = SourceContext(
        sessionId: request.headers.value('x-kazumi-session')!,
        timeout: const Duration(seconds: 45),
      );
      final job = _BrowserJob(
        _handle(),
        source.manifest.id,
        context,
        resolution ? 'resolution' : 'challenge',
      );
      if (resolution) {
        final item = _content(
          session,
          data['contentId'] as String? ?? '',
          source.manifest.id,
        );
        final lines = session.lines[item.ref.id] ?? [];
        SourceEpisode? episode;
        for (final line in lines) {
          if (line.id != data['lineId']) continue;
          for (final e in line.episodes) {
            if (e.id == data['episodeId']) episode = e;
          }
        }
        if (episode == null) {
          throw const SourceException('NOT_FOUND', '请先获取当前条目的播放线路');
        }
        job.targetUrl = episode.pageUrl;
        session.jobs[job.id] = job;
        unawaited(_resolve(session, source, job, episode.pageUrl));
      } else {
        if (!source.execution.antiCrawlerConfig.enabled ||
            source.execution.searchMode != 'xpath') {
          throw const SourceException('UNSUPPORTED', '来源未配置网页验证能力');
        }
        final keyword = data['keyword'] as String? ?? '';
        if (keyword.isEmpty || keyword.length > 300) {
          throw const SourceException('INVALID_ARGUMENT', '搜索词无效');
        }
        job.targetUrl = source.execution.searchUrl.replaceAll(
          '@keyword',
          Uri.encodeQueryComponent(keyword),
        );
        session.jobs[job.id] = job;
        unawaited(_openChallenge(session, source, job));
      }
      request.response.statusCode = 202;
      return {'data': job.toJson()};
    }
    if (path.length < baseLength + 1) {
      throw const SourceException('NOT_FOUND', '任务不存在');
    }
    final job = session.jobs[path[baseLength]];
    if (job == null ||
        job.kind != (resolution ? 'resolution' : 'challenge') ||
        DateTime.now().difference(job.createdAt) > const Duration(minutes: 2)) {
      throw const SourceException('NOT_FOUND', '任务不存在或已过期');
    }
    if (path.length == baseLength + 1 && request.method == 'DELETE') {
      await _cancel(session, job);
      return {'data': job.toJson()};
    }
    if (path.length == baseLength + 1 && request.method == 'GET') {
      if (!resolution &&
          job.backendId != null &&
          job.status == 'challenge_required') {
        // 多个调用方同时轮询时只读取一次验证上下文。
        final polling = job.polling ??= _pollChallenge(session, job);
        try {
          await polling;
        } finally {
          if (identical(job.polling, polling)) job.polling = null;
        }
      }
      return {'data': job.toJson()};
    }
    if (!resolution &&
        path.length == baseLength + 2 &&
        path.last == 'submissions' &&
        request.method == 'POST') {
      if (job.status != 'challenge_required' || job.backendId == null) {
        throw const SourceException('INVALID_ARGUMENT', '验证任务尚未就绪');
      }
      final data = await _body(request);
      final code = data['code'] as String? ?? '';
      if (code.isEmpty || code.length > 100) {
        throw const SourceException('INVALID_ARGUMENT', '验证码无效');
      }
      final config = _source(job.providerId).execution.antiCrawlerConfig;
      await session.gateway.browser('captcha', {
        'action': 'submit',
        'id': job.backendId,
        'code': code,
        'inputXpath': config.captchaInput,
        'buttonXpath': config.captchaButton,
      });
      return {'data': job.toJson()};
    }
    throw const SourceException('METHOD_NOT_ALLOWED', '任务操作不支持');
  }

  Future<void> _pollChallenge(_ApiSession session, _BrowserJob job) async {
    final backendId = job.backendId;
    final poll = await session.gateway.browser('captcha', {
      'action': 'poll',
      'id': backendId,
    }, cancelToken: job.context.cancelToken);
    job.context.checkActive();
    if (poll['image'] is String) job.result = {'image': poll['image']};
    if (poll['done'] != true) return;
    final verified = await session.gateway.browser('captcha', {
      'action': 'data',
      'id': backendId,
    }, cancelToken: job.context.cancelToken);
    job.context.checkActive();
    await session.gateway.applyVerification(
      job.providerId,
      job.targetUrl!,
      verified,
    );
    job.context.checkActive();
    job.backendId = null;
    await session.gateway.browser('captcha', {
      'action': 'close',
      'id': backendId,
    });
    job.context.checkActive();
    job.status = 'ready';
    job.result = {'verified': true};
  }

  Future<void> _resolve(
    _ApiSession session,
    SourceDefinition source,
    _BrowserJob job,
    String url,
  ) async {
    try {
      final result = await session.service.observe(
        source.manifest.id,
        'resolve',
        job.context,
        () async {
          final raw = source.toJson();
          final headers = await session.gateway.playbackHeaders(
            source.manifest.id,
            url,
            userAgent: raw['userAgent'] as String?,
            referer: raw['referer'] as String?,
          );
          final parsed = await session.gateway.browser('parse', {
            'url': url,
            'headers': headers,
            'userAgent': headers['user-agent'],
            'cookie': headers['cookie'],
            'useLegacyParser': raw['useLegacyParser'] == true,
          }, cancelToken: job.context.cancelToken);
          final media = parsed['url'];
          if (media is! String ||
              !['http', 'https'].contains(Uri.tryParse(media)?.scheme)) {
            throw const SourceException('PARSE_ERROR', '未找到视频地址');
          }
          // 媒体上下文仅保留在服务端；不将 Cookie 编码到公共 URL。
          final mediaHeaders = await session.gateway.playbackHeaders(
            source.manifest.id,
            media,
            userAgent: headers['user-agent'],
            referer: headers['referer'],
          );
          return {
            'url': _mediaUrl(media, mediaHeaders),
            'format':
                parsed['format'] ??
                (Uri.parse(media).path.endsWith('.m3u8') ? 'hls' : 'auto'),
            'expiresAt': DateTime.now()
                .add(const Duration(hours: 2))
                .toUtc()
                .toIso8601String(),
          };
        },
      );
      job.context.checkActive();
      job.result = result;
      job.status = 'ready';
    } catch (error) {
      if (job.status == 'cancelled') return;
      job.error = SourceService.mapError(error, source.manifest.id);
      job.status = job.error!.code == 'CHALLENGE_REQUIRED'
          ? 'challenge_required'
          : 'failed';
    }
  }

  Future<void> _openChallenge(
    _ApiSession session,
    SourceDefinition source,
    _BrowserJob job,
  ) async {
    try {
      final config = source.execution.antiCrawlerConfig;
      final opened = await session.gateway.browser('captcha', {
        'action': 'open',
        'url': job.targetUrl,
        'mode': config.captchaType == 2
            ? 'button'
            : config.captchaType == 3
            ? 'script'
            : 'image',
        'captchaXpath': config.captchaImage,
        'inputXpath': config.captchaInput,
        'buttonXpath': config.captchaButton,
        'script': config.captchaScript,
      }, cancelToken: job.context.cancelToken);
      job.backendId = opened['id'] as String;
      if (job.status == 'cancelled') {
        await _cancel(session, job);
        return;
      }
      job.status = 'challenge_required';
    } catch (error) {
      if (job.status == 'cancelled') return;
      job.error = SourceService.mapError(error, source.manifest.id);
      job.status = 'failed';
    }
  }

  Future<void> _cancel(_ApiSession session, _BrowserJob job) async {
    job.status = 'cancelled';
    job.context.cancelToken.cancel();
    job.result = null;
    final backendId = job.backendId;
    job.backendId = null;
    if (backendId != null) {
      try {
        await session.gateway.browser('captcha', {
          'action': 'close',
          'id': backendId,
        });
      } catch (_) {}
    }
  }
}

// 默认请求器只负责网络，XPath/JSONPath 始终由已有引擎执行。
RuleEngine gatewayEngine(SourceGateway gateway) =>
    RuleEngine(requestExecutor: gateway, logFailures: false);
