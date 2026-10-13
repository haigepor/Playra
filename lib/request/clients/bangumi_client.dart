import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_error_mapper.dart';
import 'package:kazumi/request/core/bangumi_request_policy.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/utils/bangumi_mirror_credentials.dart';
import 'package:kazumi/utils/constants.dart';
import 'package:kazumi/utils/crypto.dart';

class BangumiClient {
  BangumiClient._();

  static final BangumiClient instance = BangumiClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    String? accessToken,
    CancelToken? cancelToken,
    bool officialOnly = false,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.get(
        url,
        queryParameters: queryParameters,
        options: _options(
          requiresAuth: requiresAuth,
          accessToken: accessToken,
          url: url,
          method: 'GET',
          officialOnly: officialOnly,
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      if (!officialOnly && _canRetryOfficial(url, 'GET', e)) {
        return get(
          url,
          queryParameters: queryParameters,
          requiresAuth: requiresAuth,
          accessToken: accessToken,
          cancelToken: cancelToken,
          officialOnly: true,
        );
      }
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Future<dynamic> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    CancelToken? cancelToken,
    bool officialOnly = false,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: _options(
          requiresAuth: requiresAuth,
          url: url,
          method: 'POST',
          data: data,
          officialOnly: officialOnly,
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      if (!officialOnly && _canRetryOfficial(url, 'POST', e)) {
        return post(
          url,
          data: data,
          queryParameters: queryParameters,
          requiresAuth: requiresAuth,
          cancelToken: cancelToken,
          officialOnly: true,
        );
      }
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Options _options({
    required bool requiresAuth,
    String? accessToken,
    required String url,
    required String method,
    Object? data,
    bool officialOnly = false,
  }) {
    final headers = <String, dynamic>{...bangumiHTTPHeader};
    final bangumiSyncEnable = GStorage.getSetting(
      SettingsKeys.bangumiSyncEnable,
    );
    final token =
        (accessToken ??
                GStorage.getSetting<String>(SettingsKeys.bangumiAccessToken))
            .trim();
    if ((requiresAuth || bangumiSyncEnable) && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    final protected = isProtectedBangumiMirrorRequest(url, method);
    final hasCredentials =
        (bangumiMirrorCredentials['id'] ?? '').trim().isNotEmpty &&
        (bangumiMirrorCredentials['value'] ?? '').trim().isNotEmpty;
    // 本地 APK 不一定有 CI 密钥，空签名必然被拒；原生官方请求复用 ECH。
    final useOfficial =
        officialOnly ||
        (protected &&
            BangumiAcceleration.current == BangumiAcceleration.mirror &&
            (!hasCredentials || kIsWeb));
    if (protected &&
        !useOfficial &&
        BangumiAcceleration.current == BangumiAcceleration.mirror) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = data == null ? '' : jsonEncode(data);
      headers['X-AppId'] = bangumiMirrorCredentials['id'];
      headers['X-Timestamp'] = timestamp;
      headers['X-Signature'] = generateBangumiMirrorSearchSignature(
        method: method,
        path: Uri.parse(url).path,
        body: body,
        timestamp: timestamp,
      );
    }
    return Options(
      headers: headers,
      extra: {
        if (useOfficial)
          bangumiAccelerationOverride:
              kIsWeb ||
                  BangumiAcceleration.current == BangumiAcceleration.direct
              ? 'direct'
              : 'ech',
      },
    );
  }

  bool _canRetryOfficial(String url, String method, DioException error) =>
      BangumiAcceleration.current == BangumiAcceleration.mirror &&
      error.requestOptions.extra[bangumiAccelerationOverride] == null &&
      isProtectedBangumiMirrorRequest(url, method) &&
      const [401, 403].contains(error.response?.statusCode);
}
