import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:http/http.dart' as http;

import '../sdk_playback_models.dart';
import '../sdk_playback_provider.dart';
import '../source_models.dart' show SourceException;
import 'whisklet_catalog.dart';
import 'whisklet_client.dart';
import 'whisklet_models.dart';

/// 第二内容源（Whisklet）的播放供给：直链令牌 / 外部解析 / ajiami 家族三路。
///
/// 2026-11-03 真连取证（对照净化包 15/15 证据链）：
/// - 直链线令牌裸 GET 即 m3u8（lzcdn 线实测 200 `#EXTM3U`），无需附加请求头；
/// - `/ajiami/` 家族：`secret_parse_api_url` 反复重发直到 `data` 达满长——响应头部
///   随机截断 0..约 21 字符是信封丢头现象，非加密；满长档位按线路代号固定
///   （co=88、BBA=800…）；`player_code` 传线路自身代号（A/B 实测 co 1 轮满长，
///   硬编码 BBA 需 3 轮）；随后 GET `parse_api?url=<param>` 取 `{code:200,url}`；
/// - 外部解析器：令牌直接拼在模板后（模板自带查询参数），多数已自失效；
/// - 解析后端（coffee-api.1ljx.com）有上游自己的日点数配额：403+「点数」
///   是配额打满而非协议错误，协议层以 param 满长为通过判据。
class WhiskletPlaybackProvider extends SdkPlaybackProvider {
  WhiskletPlaybackProvider(this.catalog, {http.Client? transport})
    : _transport = transport ?? http.Client();

  final WhiskletCatalog catalog;
  final http.Client _transport;

  /// 各解析源代号的 param 满长（服务端下发真值，不得改写）。
  static const _familyFull = {
    'BBA': 800,
    'co': 88,
    'NBY': 288,
    'zijianm3u8': 172,
    'rose': 232,
    'youku': 144,
    'qq': 144,
  };

  @override
  String get id => 'whisklet';
  @override
  String get name => 'Whisklet';

  WhiskletLine _line(List<WhiskletLine> lines, String code) {
    final matches = lines.where((line) => line.code == code).toList();
    if (matches.length != 1) {
      throw const SourceException('UNKNOWN_SOURCE', '线路不存在或已下架');
    }
    return matches.single;
  }

  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async {
    final videoId = int.tryParse(id);
    if (videoId == null) {
      throw const SourceException('INVALID_REFERENCE', '内容标识无效');
    }
    final info = await catalog.info(videoId, cancel: cancel);
    final lines = await catalog.lines(videoId, cancel: cancel);
    return SdkVideoData(
      id: id,
      title: WhiskletWork.plain(info['vod_name']),
      categoryName: WhiskletWork.plain(info['vod_class']),
      cover: WhiskletWork.image(info['vod_pic']),
      poster: WhiskletWork.image(info['vod_pic_screenshot']),
      description: WhiskletWork.plain(info['vod_content']),
      year: WhiskletWork.plain(info['vod_year']),
      area: WhiskletWork.plain(info['vod_area']),
      score: double.tryParse(WhiskletWork.plain(info['vod_score'])) ?? 0,
      lines: [
        for (final line in lines)
          SdkLine(line.code, line.name.isEmpty ? line.code : line.name),
      ],
      // 电影等单线单集形态在详情页直接进播放器，不出选集列表。
      singleMovie: lines.isNotEmpty &&
          lines.every((line) => line.episodes.length <= 1),
    );
  }

  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async {
    final videoId = int.tryParse(id);
    if (videoId == null) {
      throw const SourceException('INVALID_REFERENCE', '内容标识无效');
    }
    final lines = await catalog.lines(videoId, cancel: cancel);
    final line = _line(lines, code);
    return [
      for (final episode in line.episodes)
        SdkEpisode(
          number: episode.number,
          name: episode.name,
          code: code,
          // 令牌是唯一选集身份：同剧同集名的两集也不能靠目录下标区分。
          reference: episode.token,
        ),
    ];
  }

  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    final matches = (await episodes(
      id,
      code,
      cancel: cancel,
    )).where((entry) => entry.number == episode).toList();
    if (matches.length != 1) {
      throw const SourceException('INVALID_REFERENCE', '缺少唯一对应剧集');
    }
    return playEpisode(id, code, matches.single, quality: quality, cancel: cancel);
  }

  @override
  Future<Map<String, dynamic>> playEpisode(
    String id,
    String code,
    SdkEpisode episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    final token = episode.reference;
    if (token == null || token.isEmpty) {
      throw const SourceException('INVALID_REFERENCE', '选集令牌缺失');
    }
    final videoId = int.tryParse(id);
    if (videoId == null) {
      throw const SourceException('INVALID_REFERENCE', '内容标识无效');
    }
    final lines = await catalog.lines(videoId, cancel: cancel);
    final line = _line(lines, code);

    final String url;
    if (line.parseApi.isEmpty) {
      // 直链线：令牌本身就是可播地址。
      url = token;
    } else if (line.parseApi.contains('/ajiami/')) {
      final minFull = _familyFull[line.code] ?? 64;
      final param = await _fetchParam(token, line.code, minFull, cancel);
      final resolved = await _resolveViaGet(
        line.parseApi.split('?url=')[0],
        '?url=',
        param,
      );
      if (resolved == null) {
        return {'status': 'unavailable', 'error': 'UPSTREAM_LIMIT'};
      }
      url = resolved;
    } else {
      // 外部解析器：模板自带查询参数，令牌直接拼接。
      final resolved = await _resolveViaGet(line.parseApi, '', token);
      if (resolved == null) {
        return {'status': 'unavailable', 'error': 'UPSTREAM_LIMIT'};
      }
      url = resolved;
    }
    if (url.isEmpty) {
      return {'status': 'unavailable', 'error': 'INVALID_MEDIA'};
    }
    return {
      'status': 'ready',
      'media': {'url': url},
      'selection': {'videoId': id, 'code': code, 'episodeRef': token},
    };
  }

  /// 家族 param 轮询：信封丢头会截断 `5 + 16k` 字符（导致长度 `mod 4 == 3`），
  /// 完整未截断的 Base64 参数必满足 `length >= minFull && length % 4 == 0`。
  Future<String> _fetchParam(
    String token,
    String playerCode,
    int minFull,
    CancelToken? cancel,
  ) async {
    var best = '';
    for (var round = 1; round <= 10; round++) {
      if (cancel?.isCancelled == true) {
        throw const SourceException('CANCELLED', '请求已取消');
      }
      final batch = await Future.wait(
        List.generate(3, (_) => _paramRound(token, playerCode, '')),
      );
      for (final candidate in batch) {
        if (candidate.length > best.length) best = candidate;
        if (_isCompleteParam(candidate, minFull)) return candidate;
      }
      if (_isCompleteParam(best, minFull)) return best;
      if (round < 10) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    throw SourceException(
      'PARAM_INCOMPLETE',
      '解析参数未达完整长度（${best.length}/$minFull）',
    );
  }

  static bool _isCompleteParam(String value, int minFull) =>
      value.length >= minFull && value.length % 4 == 0;

  Future<String> _paramRound(
    String token,
    String playerCode,
    String best,
  ) async {
    try {
      final result = await catalog.client.call(WhiskletMethod.secretParse, {
        'url': token,
        'player_code': playerCode,
        'token': '',
      });
      final value = result['data'];
      if (value is String && value.length > best.length) return value;
      return best;
    } on SourceException catch (error) {
      // 本轮响应连基础结构都不完整（丢头更狠），交给下一轮重发。
      if (error.code == 'PROTOCOL') return best;
      rethrow;
    }
  }

  /// 解析接口（家族与外部共用）：GET 返回 JSON `{code:200,url}`。
  /// 返回 null = 上游配额打满（可重试的暂时态），其余失败抛异常。
  Future<String?> _resolveViaGet(
    String base,
    String joiner,
    String value,
  ) async {
    final response = await _transport
        .get(Uri.parse('$base$joiner$value'))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw SourceException('PARSER', '解析器响应异常（HTTP ${response.statusCode}）');
    }
    final Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map,
      );
    } catch (_) {
      throw const SourceException('PARSER', '该线路解析失败，请切换其他线路');
    }
    final status = payload['code'];
    if (status == 403) {
      // 上游解析后端的日点数配额（coffee-api）：配额打满不是协议错误。
      return null;
    }
    if (status != 200 || payload['url'] is! String) {
      throw const SourceException('PARSER', '该线路解析失败，请切换其他线路');
    }
    final url = Uri.tryParse(payload['url'] as String);
    if (url == null || !['http', 'https'].contains(url.scheme)) {
      throw const SourceException('PARSER', '该线路解析结果无效');
    }
    return url.toString();
  }

  void dispose() {
    _transport.close();
  }
}
