import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../source_models.dart' show SourceException;
import 'whisklet_codec.dart';

/// 上游方法名与响应 `data` 形状一一对应；新增方法必须同时在 [WhiskletClient.call]
/// 的校验表里声明类型，否则拒绝解析。
enum WhiskletMethod {
  appConfig('app_config'),
  nav('nav'),
  recommend('index_recommend'),
  videoList('video_list'),
  search('search'),
  ranks('rank_list'),
  detail('video_detail'),
  secretParse('secret_parse_api_url');

  const WhiskletMethod(this.wireName);
  final String wireName;
}

class WhiskletClient {
  WhiskletClient({
    http.Client? transport,
    Uri? endpoint,
    this.timeout = const Duration(seconds: 12),
  }) : _transport = transport ?? http.Client(),
       _endpoint = endpoint;

  final http.Client _transport;
  final Uri? _endpoint;
  final Duration timeout;
  bool _closed = false;

  Uri get endpoint => _endpoint ?? WhiskletProfile.endpoint;

  Future<Map<String, dynamic>> call(
    WhiskletMethod method, [
    Map<String, dynamic> data = const {'token': ''},
    CancelToken? cancel,
  ]) async {
    if (_closed) throw const SourceException('CLOSED', '内容源已关闭');
    if (cancel?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
    final payload = WhiskletCodec().encrypt({
      'method': method.wireName,
      'data': data,
      'csrf': DateTime.now().millisecondsSinceEpoch,
    });
    final http.Response response;
    try {
      response = await _transport
          .post(endpoint, body: payload, headers: WhiskletProfile.headers)
          .timeout(timeout);
    } on TimeoutException {
      throw const SourceException('TIMEOUT', '内容源响应超时，请重试');
    } catch (_) {
      throw const SourceException('NETWORK', '无法连接内容源，请检查网络后重试');
    }
    if (response.statusCode != 200) {
      throw SourceException('HTTP', '内容源请求失败（HTTP ${response.statusCode}）');
    }
    if (cancel?.isCancelled == true) {
      throw const SourceException('CANCELLED', '请求已取消');
    }
    final Map<String, dynamic> result;
    try {
      final rawText = utf8.decode(response.bodyBytes);
      result = response.bodyBytes.length > 16384
          ? await compute(decodeWhiskletResponse, (rawText, method.wireName))
          : decodeWhiskletResponse((rawText, method.wireName));
    } catch (_) {
      throw const SourceException('PROTOCOL', '内容源返回不完整或格式已变更');
    }
    if (result['code'] != 1) {
      throw const SourceException('BUSINESS_REJECTED', '内容源拒绝了本次请求');
    }
    final value = result['data'];
    final valid = switch (method) {
      WhiskletMethod.nav => value is List,
      WhiskletMethod.recommend => value is Map,
      WhiskletMethod.detail => value is Map,
      // 两种载荷都是字符串：最终解析 JSON（长）与家族 param 的截断形态
      // （信封丢头，短于 32 属正常，由上层按满长重试，不视为协议错误）。
      WhiskletMethod.secretParse => value is String,
      _ => value is List,
    };
    if (!valid) {
      throw const SourceException('PROTOCOL', '内容源返回的数据结构异常');
    }
    return result;
  }

  Future<Map<String, dynamic>> videoList(
    int category,
    int page, {
    int limit = 21,
    Map<String, String> filters = const {},
    CancelToken? cancel,
  }) => call(WhiskletMethod.videoList, {
    'tid': category,
    'pg': page,
    'limit': limit,
    ...filters,
  }, cancel);

  Future<Map<String, dynamic>> recommend({CancelToken? cancel}) =>
      call(WhiskletMethod.recommend, {'token': ''}, cancel);

  Future<Map<String, dynamic>> detail(int id, {CancelToken? cancel}) =>
      call(WhiskletMethod.detail, {'id': id}, cancel);

  Future<Map<String, dynamic>> ranks({CancelToken? cancel}) =>
      call(WhiskletMethod.ranks, {'token': ''}, cancel);

  Future<Map<String, dynamic>> search(
    String keyword,
    int page, {
    CancelToken? cancel,
  }) => call(WhiskletMethod.search, {
    'text': keyword,
    'pg': page,
    'token': '',
  }, cancel);

  /// 解析器：上游下发网页地址，解析接口回 `{code:200,url:<直链>}`。
  Future<Uri> parse(
    String url,
    String playerCode, {
    CancelToken? cancel,
  }) async {
    final data = await call(WhiskletMethod.secretParse, {
      'url': url,
      'player_code': playerCode,
      'token': '',
    }, cancel);
    final value = data['data'];
    if (value is! String) {
      throw const SourceException('PROTOCOL', '解析结果格式异常');
    }
    final resolved = jsonDecode(value);
    if (resolved is! Map ||
        resolved['code'] != 200 ||
        resolved['url'] is! String ||
        (resolved['url'] as String).trim().isEmpty) {
      throw const SourceException('PARSER', '该线路解析失败，请切换其他线路');
    }
    final uri = Uri.tryParse(resolved['url'] as String);
    if (uri == null || !['http', 'https'].contains(uri.scheme)) {
      throw const SourceException('PARSER', '该线路解析结果无效');
    }
    return uri;
  }

  void close() {
    _closed = true;
    _transport.close();
  }
}
