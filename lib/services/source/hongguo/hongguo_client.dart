/// 红果短剧匿名客户端（对标 openhongguo sdk/client.go / catalog.go /
/// series.go / media.go / rank.go 的读取面）。
///
/// 用匿名设备发送所有请求：首次调用自动注册并落盘档案；设备被拒或播放
/// 空结果时自动换新设备重试（最多 2 次）。纯 Dart，dio 传输。
library;

import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart'
    show CancelToken, Dio, Options, Response, ResponseType;

import 'hongguo_device.dart';
import 'hongguo_models.dart';
import 'hongguo_parse.dart';
import 'hongguo_protocol.dart';
import 'hongguo_sign.dart';
import 'hongguo_spade.dart';

/// 客户端错误；[kind] 供调用方决定重试/换设备/放弃。
class HongguoClientError implements Exception {
  HongguoClientError(
    this.message, {
    this.kind = HongguoErrorKind.unknown,
    this.code = 0,
    this.retryable = false,
    this.retryAfterMs = 0,
    this.httpStatus = 0,
  });

  final String message;
  final HongguoErrorKind kind;
  final int code;
  final bool retryable;
  final int retryAfterMs;
  final int httpStatus;

  @override
  String toString() =>
      'HongguoClientError(${kind.name}${code != 0 ? ' $code' : ''}): $message';
}

/// 书城频道一页（含无限流句柄）。
class HongguoDiscoverPage {
  const HongguoDiscoverPage({required this.page, required this.next});

  final HongguoCatalogPage page;

  /// cell/change 翻页句柄；没有下一页时为 null。
  final HongguoFeedContinuation? next;
}

class HongguoClient {
  HongguoClient({
    required HongguoProfileStore profileStore,
    Dio? transport,
    this.retryAttempts = 4,
    this.deviceResets = 2,
    this.timeout = const Duration(seconds: 15),
    String? apiOrigin,
    String? registerOrigin,
    this.onDebugResponse,
  })  : _profileStore = profileStore,
        _dio = transport ?? Dio(),
        apiOrigin = (apiOrigin ?? 'https://$hongguoApiHost').replaceAll(RegExp(r'/+$'), ''),
        registerOrigin =
            (registerOrigin ?? 'https://$hongguoRegisterHost').replaceAll(RegExp(r'/+$'), '') {
    _dio.options
      ..connectTimeout = timeout
      ..receiveTimeout = timeout
      ..responseType = ResponseType.bytes
      ..validateStatus = (_) => true;
  }

  final HongguoProfileStore _profileStore;
  final Dio _dio;
  final int retryAttempts;
  final int deviceResets;
  final Duration timeout;
  final String apiOrigin;
  final String registerOrigin;

  /// 调试钩子：每个成功响应回传 (路径, 已解码 JSON)。
  final void Function(String path, Object? body)? onDebugResponse;

  HongguoDeviceProfile? _profile;
  bool _registering = false;
  int _resetGeneration = 0;

  // ---------------------------------------------------------------------
  // 设备与注册
  // ---------------------------------------------------------------------

  Future<HongguoDeviceProfile> _ensureGuest({bool needTicket = false}) async {
    while (_registering) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _registering = true;
    try {
      var p = _profile ?? await _profileStore.load();
      if (p != null) {
        // 旧档案未固定机型时补上默认设备并落盘。
        p.device = p.device.orDefault();
      }
      if (p != null && p.ready && (!needTicket || p.ttReq.isNotEmpty)) {
        _profile = p;
        return p;
      }
      p ??= newAnonymousDeviceProfile();
      _profile = p;
      await _profileStore.save(p);
      return await _register(p, needTicket: needTicket);
    } finally {
      _registering = false;
    }
  }

  Future<HongguoDeviceProfile> _register(
    HongguoDeviceProfile p, {
    bool needTicket = false,
  }) async {
    final body = buildRegisterBody(
      HongguoRegisterIdentity(
        cdId: p.cdId,
        openUdId: p.openUdId,
        clientUdId: p.clientUdId,
        oaId: p.oaId,
        reqId: p.reqId,
        device: p.device,
      ),
      DateTime.now(),
    );
    final ticket = DateTime.now().millisecondsSinceEpoch;
    final headers = <String, String>{
      'User-Agent': hongguoUserAgent(p.device),
      'Content-Type': 'application/octet-stream;tt-data=a',
      'log-encode-type': 'gzip',
      'sdk-version': '2',
      'passport-sdk-version': '5051452',
      'x-vc-bdturing-sdk-version': '4.0.3.cn',
      'x-ss-dp': hongguoAID,
      'X-SS-STUB': contentMD5(body),
      'x-reading-request': readingRequestID(ticket, _randomInt31()),
    };
    final raw = await _do(
      'POST',
      registerOrigin,
      pathRegister,
      query: {'req_id': p.reqId, 'tt_data': 'a'},
      headers: headers,
      body: body,
    );
    final parsed = parseRegister(raw);
    if (parsed == null) {
      throw HongguoClientError(
        'anonymous registration returned no guest identity',
        kind: HongguoErrorKind.auth,
      );
    }
    p.deviceId = parsed.deviceId;
    p.installId = parsed.installId;
    p.deviceToken = '';
    if (needTicket && p.ttReq.isEmpty) {
      throw HongguoClientError(
        'guest ticket missing',
        kind: HongguoErrorKind.rateLimited,
        retryable: true,
      );
    }
    await _profileStore.save(p);
    return p;
  }

  Future<void> resetDevice() async {
    await _profileStore.reset();
    _profile = null;
    _resetGeneration++;
    await _ensureGuest();
  }

  HongguoSearchIdentity _identity(HongguoDeviceProfile p) {
    return HongguoSearchIdentity(
      deviceId: p.deviceId,
      installId: p.installId,
      cdId: p.cdId,
      openUdId: p.openUdId,
      device: p.device.orDefault(),
    );
  }

  int _randomInt31() => Random.secure().nextInt(0x7FFFFFFF);

  // ---------------------------------------------------------------------
  // 传输
  // ---------------------------------------------------------------------

  Future<Object?> _do(
    String method,
    String origin,
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    List<int>? body,
    CancelToken? cancel,
  }) async {
    final url = Uri.parse(origin + path).replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    ).toString();
    final raw = await _doRaw(
      method,
      url,
      headers ?? const {},
      body,
      cancel: cancel,
    );
    return jsonDecode(utf8.decode(raw));
  }

  /// 发送已签名的原始 URL；带重试与错误归类。
  Future<Uint8List> _doRaw(
    String method,
    String rawURL,
    Map<String, String> headers,
    List<int>? body, {
    CancelToken? cancel,
  }) async {
    for (var attempt = 0;; attempt++) {
      _checkCancel(cancel);
      final (raw, status, setCookies) = await _doOnce(
        method,
        rawURL,
        headers,
        body,
        cancel,
      );
      final err = _classifyResponse(raw, status);
      if (err == null) {
        if (setCookies.isNotEmpty && _profile != null) {
          _applyGuestCookies(_profile!, setCookies);
        }
        if (onDebugResponse != null) {
          try {
            onDebugResponse!(rawURL, jsonDecode(utf8.decode(raw)));
          } catch (_) {}
        }
        return raw;
      }
      final retryable = _isRetryable(err);
      if (!retryable || attempt + 1 >= retryAttempts) throw err;
      var wait = Duration(milliseconds: 300 * (1 << attempt));
      if (wait > const Duration(seconds: 5)) {
        wait = const Duration(seconds: 5);
      }
      wait = _applyBanWindow(err, wait);
      if (wait > const Duration(seconds: 10)) {
        throw HongguoClientError(
          '${err.message}; service asks to wait ~${wait.inSeconds}s',
          kind: err.kind,
          code: err.code,
          retryAfterMs: wait.inMilliseconds,
        );
      }
      await Future<void>.delayed(wait);
    }
  }

  void _checkCancel(CancelToken? cancel) {
    if (cancel?.isCancelled == true) {
      throw HongguoClientError('cancelled', kind: HongguoErrorKind.unknown);
    }
  }

  Future<(Uint8List, int, List<(String, String)>)> _doOnce(
    String method,
    String rawURL,
    Map<String, String> headers,
    List<int>? body,
    CancelToken? cancel,
  ) async {
    final h = Map<String, String>.from(headers);
    h.putIfAbsent('Accept', () => 'application/json');
    final Response<List<int>> resp;
    try {
      resp = await _dio.request<List<int>>(
        rawURL,
        options: Options(
          method: method,
          headers: h,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
          receiveTimeout: timeout,
        ),
        data: body,
        cancelToken: cancel,
      );
    } catch (e) {
      if (cancel?.isCancelled == true) {
        throw HongguoClientError('cancelled', kind: HongguoErrorKind.unknown);
      }
      throw HongguoClientError(
        'transport failure: $e',
        kind: HongguoErrorKind.unknown,
        retryable: true,
      );
    }
    _checkCancel(cancel);
    var bytes = resp.data ?? Uint8List(0);
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      bytes = _gunzip(bytes);
    }
    // 读 Set-Cookie（dio 已把多值合并，按名字前缀拆开）。
    final setCookies = <(String, String)>[];
    resp.headers.forEach((name, values) {
      if (name.toLowerCase() != 'set-cookie') return;
      for (final merged in values) {
        for (final part in merged.split(', ')) {
          final kv = part.split('=');
          if (kv.length >= 2) {
            setCookies.add((kv[0].trim(), kv[1].split(';').first.trim()));
          }
        }
      }
    });
    return (Uint8List.fromList(bytes), resp.statusCode ?? 0, setCookies);
  }

  /// 响应分类；null 表示成功。
  HongguoClientError? _classifyResponse(Uint8List raw, int status) {
    switch (status) {
      case 401:
      case 403:
        return HongguoClientError(
          'authentication required',
          kind: HongguoErrorKind.auth,
          httpStatus: status,
        );
      case 429:
        return HongguoClientError(
          'rate limited',
          kind: HongguoErrorKind.rateLimited,
          retryable: true,
          httpStatus: status,
        );
    }
    if (status < 200 || status >= 300) {
      return HongguoClientError(
        'HTTP request failed ($status)',
        kind: HongguoErrorKind.unknown,
        retryable: status == 0 || status >= 500,
        httpStatus: status,
      );
    }
    final body = Uint8List.fromList(raw);
    if (_isBlank(body)) {
      return HongguoClientError(
        'anonymous response was empty',
        kind: HongguoErrorKind.unknown,
      );
    }
    Object? root;
    try {
      root = jsonDecode(utf8.decode(body));
    } catch (_) {
      root = null;
    }
    final bc = businessCode(root);
    if (bc != null && bc.$1.isNotEmpty && bc.$1 != '0') {
      final code = int.tryParse(bc.$1);
      final kind = code != null
          ? classifyCode(code, bc.$2)
          : classifyCode(0, bc.$2);
      return HongguoClientError(
        bc.$2.isEmpty ? 'code ${bc.$1}' : bc.$2,
        kind: kind,
        code: code ?? 0,
        retryable: kind == HongguoErrorKind.rateLimited,
      );
    }
    final status0 = baseStatus(root);
    if (deviceRejectedStatus(status0)) {
      return HongguoClientError(
        'device rejected',
        kind: HongguoErrorKind.deviceRejected,
        code: status0,
      );
    }
    return null;
  }

  bool _isRetryable(HongguoClientError err) =>
      err.retryable ||
      err.kind == HongguoErrorKind.rateLimited ||
      (err.httpStatus == 0 || err.httpStatus >= 500) &&
          err.kind == HongguoErrorKind.unknown;

  Duration _applyBanWindow(HongguoClientError err, Duration fallback) {
    final (minBan, maxBan) = banWindow(err.message) ?? (0, 0);
    if (maxBan <= 0 && minBan <= 0) return fallback;
    if (maxBan > minBan && minBan > 0) {
      return Duration(seconds: minBan + (maxBan - minBan) ~/ 2);
    }
    return Duration(seconds: maxBan > 0 ? maxBan : minBan);
  }

  void _applyGuestCookies(HongguoDeviceProfile p, List<(String, String)> cookies) {
    for (final (name, value) in cookies) {
      switch (name.toLowerCase()) {
        case 'ttreq':
          if (value.isNotEmpty) p.ttReq = value;
        case 'store-region':
          if (value.isNotEmpty) p.storeRegion = value;
        case 'store-region-src':
          if (value.isNotEmpty) p.storeRegionSrc = value;
      }
    }
  }

  // ---------------------------------------------------------------------
  // 设备换新包装
  // ---------------------------------------------------------------------

  Future<T> _withFreshDevice<T>(
    bool playback,
    Future<T> Function() call,
  ) async {
    for (var i = 0;; i++) {
      final gen = _resetGeneration;
      try {
        return await call();
      } on HongguoClientError catch (e) {
        final needs = e.kind == HongguoErrorKind.deviceRejected ||
            (playback && e.message == 'anonymous response was empty');
        if (i >= deviceResets || !needs) rethrow;
        if (_resetGeneration != gen) continue; // 其他调用刚换过设备
        await resetDevice();
      }
    }
  }

  // ---------------------------------------------------------------------
  // 读取面
  // ---------------------------------------------------------------------

  Map<String, String> _anonymousHeaders(
    HongguoDeviceProfile p,
    int ticket,
    Map<String, String> signed,
  ) {
    final headers = Map<String, String>.from(signed);
    headers['User-Agent'] = hongguoUserAgent(p.device);
    headers['x-ss-dp'] = hongguoAID;
    headers['lc'] = '101';
    headers['x-reading-request'] = readingRequestID(ticket, _randomInt31());
    if (p.ttReq.isNotEmpty) {
      headers['Cookie'] = p.guestCookie;
    }
    return headers;
  }

  /// 搜索一页。[cursor] 是上一页给的下一页 offset（'' = 第一页）。
  Future<HongguoCatalogPage> search(
    String query, {
    String cursor = '',
    int pageSize = 20,
    CancelToken? cancel,
  }) {
    return _withFreshDevice(false, () async {
      if (query.isEmpty) {
        throw HongguoClientError('missing search query',
            kind: HongguoErrorKind.param);
      }
      final offset = int.tryParse(cursor.trim()) ?? 0;
      final p = await _ensureGuest(needTicket: true);
      final pairs = signedSearchPairsFor(
        _identity(p),
        query,
        count: pageSize,
        offset: offset,
      );
      final ticket = DateTime.now().millisecondsSinceEpoch;
      final (sq, headers) = hongguoSignRequest(
        pathSearch,
        pairs,
        ticket,
        p.deviceId,
        hongguoVersionName,
      );
      final raw = await _doRaw(
        'GET',
        '$apiOrigin$pathSearch?${sq.query}',
        _anonymousHeaders(p, ticket, headers),
        null,
        cancel: cancel,
      );
      final page = parseSearchTab(jsonDecode(utf8.decode(raw)), 11);
      if (page == null || page.items.isEmpty) {
        throw HongguoClientError(
          'anonymous response was empty',
          kind: HongguoErrorKind.unknown,
        );
      }
      return page;
    });
  }

  /// 书城频道一页。推荐频道第一页可直接取无限流句柄。
  Future<HongguoDiscoverPage> discover({
    HongguoDiscoverChannel channel = hongguoChannelRecommend,
    HongguoFeedContinuation? next,
    CancelToken? cancel,
  }) {
    return _withFreshDevice(false, () async {
      final p = await _ensureGuest(needTicket: true);
      if (next == null) {
        final pairs = signedDiscoverPairsIn(
          _identity(p),
          tabType: channel.requestTab,
          bottom: channel.bottomTab,
        );
        final ticket = DateTime.now().millisecondsSinceEpoch;
        final (sq, headers) = hongguoSignRequest(
          pathSearch, // GET 的 medusa 均以 search 路径签名（线上实测接受）
          pairs,
          ticket,
          p.deviceId,
          hongguoVersionName,
        );
        final raw = await _doRaw(
          'GET',
          '$apiOrigin$pathDiscover?${sq.query}',
          _anonymousHeaders(p, ticket, headers),
          null,
          cancel: cancel,
        );
        final root = jsonDecode(utf8.decode(raw));
        final page = parseDiscoverTab(root, channel.responseTab);
        final cont = discoverContinuation(root, channel.responseTab);
        return HongguoDiscoverPage(page: page ?? const HongguoCatalogPage(items: []), next: cont);
      }
      final pairs = signedCellChangePairs(
        _identity(p),
        cellId: next.cellId,
        sessionId: next.sessionId,
        showType: next.showType,
        tabType: next.tabType,
        clientTemplate: next.clientTemplate,
        // 服务端按 offset 续页；丢了它会永远拉回第一页（去重后表现为触底无新数据）。
        offset: next.offset.isEmpty ? '0' : next.offset,
      );
      final ticket = DateTime.now().millisecondsSinceEpoch;
      final (sq, headers) = hongguoSignRequest(
        pathSearch,
        pairs,
        ticket,
        p.deviceId,
        hongguoVersionName,
      );
      final raw = await _doRaw(
        'GET',
        '$apiOrigin$pathCellChange?${sq.query}',
        _anonymousHeaders(p, ticket, headers),
        null,
        cancel: cancel,
      );
      final page = parseCellChange(jsonDecode(utf8.decode(raw)));
      return HongguoDiscoverPage(
        page: page ?? const HongguoCatalogPage(items: []),
        next: page != null && page.hasMore && page.nextOffset > 0
            ? (
                cellId: next.cellId,
                sessionId: page.sessionId.isNotEmpty
                    ? page.sessionId
                    : next.sessionId,
                clientTemplate: next.clientTemplate,
                showType: next.showType,
                tabType: next.tabType,
                offset: '${page.nextOffset}',
              )
            : null,
      );
    });
  }

  /// 短剧榜单（tab_type 26 的 cell/change）。默认取真人剧全部榜单第一页。
  Future<HongguoShortRanking> shortRank({
    String content = 'content_type_short_play',
    String list = '',
    int offset = 0,
    List<String> seen = const [],
    String session = '',
    CancelToken? cancel,
  }) {
    return _withFreshDevice(false, () async {
      final p = await _ensureGuest(needTicket: true);
      final pairs = signedShortRankPairs(
        _identity(p),
        content: content,
        list: list,
        offset: offset,
        seen: seen,
        session: session,
      );
      final ticket = DateTime.now().millisecondsSinceEpoch;
      final (sq, headers) = hongguoSignRequest(
        pathSearch,
        pairs,
        ticket,
        p.deviceId,
        hongguoVersionName,
      );
      final raw = await _doRaw(
        'GET',
        '$apiOrigin$pathCellChange?${sq.query}',
        _anonymousHeaders(p, ticket, headers),
        null,
        cancel: cancel,
      );
      final ranking = parseShortRank(jsonDecode(utf8.decode(raw)));
      if (ranking == null) {
        throw HongguoClientError(
          'short rank parse failed',
          kind: HongguoErrorKind.unknown,
        );
      }
      return ranking;
    });
  }

  /// 搜索页热搜（猜你想搜 + 各榜）。
  Future<HongguoHotSearch> hotSearch({CancelToken? cancel}) {
    return _withFreshDevice(false, () async {
      final p = await _ensureGuest(needTicket: true);
      final pairs = signedHotSearchPairs(_identity(p));
      final ticket = DateTime.now().millisecondsSinceEpoch;
      final (sq, headers) = hongguoSignRequest(
        pathSearch,
        pairs,
        ticket,
        p.deviceId,
        hongguoVersionName,
      );
      final raw = await _doRaw(
        'GET',
        '$apiOrigin$pathPlan?${sq.query}',
        _anonymousHeaders(p, ticket, headers),
        null,
        cancel: cancel,
      );
      final hs = parseHotSearch(jsonDecode(utf8.decode(raw)));
      if (hs == null) {
        throw HongguoClientError(
          'hot search parse failed',
          kind: HongguoErrorKind.unknown,
        );
      }
      return hs;
    });
  }

  /// 短剧详情。
  Future<(HongguoSeries, List<HongguoEpisode>)> getSeries(
    String seriesId, {
    CancelToken? cancel,
  }) {
    return _withFreshDevice(false, () async {
      return await _seriesDetail(seriesId, cancel: cancel);
    });
  }

  /// 分集列表（video_detail 的 video_list）。
  Future<List<HongguoEpisode>> listEpisodes(
    String seriesId, {
    CancelToken? cancel,
  }) {
    return _withFreshDevice(false, () async {
      final (_, episodes) = await _seriesDetail(seriesId, cancel: cancel);
      if (episodes.isEmpty) {
        throw HongguoClientError(
          'anonymous response was empty',
          kind: HongguoErrorKind.unknown,
        );
      }
      return episodes;
    });
  }

  Future<(HongguoSeries, List<HongguoEpisode>)> _seriesDetail(
    String seriesId, {
    CancelToken? cancel,
  }) async {
    if (!_validID(seriesId)) {
      throw HongguoClientError('invalid series ID',
          kind: HongguoErrorKind.param);
    }
    final p = await _ensureGuest(needTicket: true);
    final body = seriesBody(seriesId);
    final ticket = DateTime.now().millisecondsSinceEpoch;
    final (sq, headers) = hongguoSignRequest(
      pathSeries,
      deviceQueryPairs(_identity(p)),
      ticket,
      p.deviceId,
      hongguoVersionName,
      body,
    );
    final raw = await _doRaw(
      'POST',
      '$apiOrigin$pathSeries?${sq.query}',
      _anonymousHeaders(p, ticket, headers),
      body,
      cancel: cancel,
    );
    final parsed = parseSeries(jsonDecode(utf8.decode(raw)));
    if (parsed == null) {
      throw HongguoClientError(
        'series response missing id or title',
        kind: HongguoErrorKind.unknown,
      );
    }
    return parsed;
  }

  /// 一集的播放模型 +（加密时的）内容密钥。
  /// 所有流共用同一密钥（同一集各清晰度的 spade_a 相同）。
  Future<(HongguoPlayback, HongguoContentKey?)> resolvePlayback(
    String episodeId, {
    CancelToken? cancel,
  }) {
    return _withFreshDevice(true, () async {
      if (!_validID(episodeId)) {
        throw HongguoClientError('invalid episode ID',
            kind: HongguoErrorKind.param);
      }
      final p = await _ensureGuest(needTicket: true);
      final body = playbackBody(episodeId);
      final ticket = DateTime.now().millisecondsSinceEpoch;
      final (sq, headers) = hongguoSignRequest(
        pathPlayback,
        deviceQueryPairs(_identity(p)),
        ticket,
        p.deviceId,
        hongguoVersionName,
        body,
      );
      final raw = await _doRaw(
        'POST',
        '$apiOrigin$pathPlayback?${sq.query}',
        _anonymousHeaders(p, ticket, headers),
        body,
        cancel: cancel,
      );
      final pb = parsePlayback(jsonDecode(utf8.decode(raw)), episodeId);
      if (pb == null) {
        throw HongguoClientError(
          'playback model unavailable',
          kind: HongguoErrorKind.unknown,
        );
      }
      if (!pb.protected) return (pb, null);
      return (pb, _deriveKey(pb));
    });
  }

  HongguoContentKey? _deriveKey(HongguoPlayback pb) {
    if (pb.keyMaterial.isEmpty) return null;
    try {
      final k = deriveHongguoContentKey(pb.keyMaterial);
      return HongguoContentKey(hex: k.hex, version: k.version);
    } on HongguoKeyMaterialError {
      return null;
    }
  }

  bool _validID(String id) {
    if (id.length < 4 || id.length > 25) return false;
    for (var i = 0; i < id.length; i++) {
      final c = id.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  void dispose() {
    _dio.close();
  }
}

/// gzip 解压兜底：响应被标 gzip 但传输层未解时手动还原。
Uint8List _gunzip(List<int> data) {
  try {
    return Uint8List.fromList(GZipCodec().decode(data));
  } catch (_) {
    return Uint8List.fromList(data);
  }
}

bool _isBlank(Uint8List body) {
  for (final b in body) {
    if (b != 0x20 && b != 0x09 && b != 0x0A && b != 0x0D) return false;
  }
  return true;
}
