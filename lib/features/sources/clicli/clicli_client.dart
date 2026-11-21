/// CliCli transport: request signing, esdk-v3 envelopes, clock calibration,
/// session-key negotiation and envelope error mapping.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;
import 'package:dio/dio.dart';

import '../../../request/core/dio_factory.dart';
import '../../../request/core/network_config.dart';
import '../core/media_source.dart';
import 'clicli_config.dart';
import 'protocol/esdk_v3.dart';

class CliCliClient {
  CliCliClient({Dio? dio}) : _injectedDio = dio {
    _sessionId = _hex(8);
  }

  final Dio? _injectedDio;
  Dio? _dio;
  int _dioRevision = -1;
  final Random _random = Random.secure();

  /// Lazily builds a proxy-aware client and rebuilds it after proxy settings
  /// change. Injected clients (tests) are used as-is and are never closed by
  /// this object.
  Dio get _client {
    final injected = _injectedDio;
    if (injected != null) return injected;
    final revision = NetworkConfig.revision;
    if (_dio == null || _dioRevision != revision) {
      _dio?.close(force: true);
      final dio = DioFactory.createForConfig(
        NetworkConfig.fromSettings(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      dio.options
        ..baseUrl = CliCliConfig.baseUrl
        ..responseType = ResponseType.bytes
        ..validateStatus = (_) => true;
      _dio = dio;
      _dioRevision = revision;
    }
    return _dio!;
  }

  String _sessionSecret = CliCliConfig.bootstrapSessionSecret;
  int _keyVersion = 1;

  double _timeOffsetSeconds = 0;
  bool _timeSynced = false;

  late final String _sessionId;
  Future<void>? _negotiating;

  /// True once the current session key was issued by `auth/negotiate`.
  bool get negotiated => _negotiated;

  bool _negotiated = false;

  int get keyVersion => _keyVersion;

  int get nowMs =>
      DateTime.now().millisecondsSinceEpoch +
      (_timeOffsetSeconds * 1000).round();

  int get nowSeconds => nowMs ~/ 1000;

  Uint8List get _sessionKey => Uint8List.fromList(ascii.encode(_sessionSecret));

  // ------------------------------------------------------------------ public

  /// Encrypted POST + envelope unwrap. Throws [MediaSourceException].
  Future<Map<String, dynamic>> callData(
    String path,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) async {
    Map<String, dynamic> json;
    try {
      json = await _callOnce(path, payload, timeout: timeout);
    } on MediaSourceException catch (error) {
      final code = error.code;
      if (code == 4020) {
        await _recoverSession();
        json = await _callOnce(path, payload, timeout: timeout);
      } else if (code == 4012 || code == 4013) {
        throw MediaSourceException(
          MediaSourceErrorKind.authentication,
          '登录状态已失效',
          code: code,
          cause: error,
        );
      } else {
        rethrow;
      }
    }
    return dataOf(json);
  }

  /// Validates `code` and returns the `data` object. CliCli uses code 200 for
  /// success; 0 shows up on a few older handlers.
  Map<String, dynamic> dataOf(Map<String, dynamic> json) {
    final code = _asInt(json['code']);
    if (code != null && code != 0 && code != 200) {
      throw _apiError(code, _asString(json['msg'] ?? json['message']));
    }
    final data = json['data'];
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return const <String, dynamic>{};
  }

  /// Re-negotiate the per-device session key. Single-flight: concurrent callers
  /// share one request.
  Future<void> negotiate() {
    final running = _negotiating;
    if (running != null) return running;
    final future = _doNegotiate().whenComplete(() => _negotiating = null);
    _negotiating = future;
    return future;
  }

  /// Drop cached session state (used by tests / after a protocol failure).
  void resetSession() {
    _sessionSecret = CliCliConfig.bootstrapSessionSecret;
    _keyVersion = 1;
    _negotiated = false;
    _negotiating = null;
  }

  void close() => _dio?.close(force: true);

  // ----------------------------------------------------------------- request

  Future<Map<String, dynamic>> _callOnce(
    String path,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) async {
    final wire = _encryptJson(payload);
    final response = await _post(path, wire, timeout: timeout);
    final json = _decode(response);
    _applyTimestamp(json);
    return json;
  }

  Future<Response<List<int>>> _post(
    String path,
    List<int> body, {
    Duration? timeout,
    Map<String, String>? overrideHeaders,
  }) async {
    try {
      return await _client.post<List<int>>(
        path,
        data: body,
        options: Options(
          headers: overrideHeaders ?? _headers(encrypted: true),
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
          receiveTimeout: timeout ?? const Duration(seconds: 20),
        ),
      );
    } on DioException catch (error) {
      throw MediaSourceException(
        MediaSourceErrorKind.network,
        _networkMessage(error),
        retryable: true,
        cause: error,
      );
    }
  }

  Map<String, String> _headers({required bool encrypted}) {
    final ts = nowMs.toString();
    final nonce = _hex(16);
    final signature = c.md5
        .convert(
          ascii.encode(
            '$ts$nonce${CliCliConfig.appId}${CliCliConfig.signSecret}',
          ),
        )
        .toString();
    return <String, String>{
      'User-Agent': CliCliConfig.userAgent,
      'Accept': 'application/json',
      if (encrypted) 'Content-Type': 'application/octet-stream',
      'X-Device-Id': CliCliConfig.deviceId,
      'X-Device-Fingerprint': CliCliConfig.deviceFingerprint,
      'X-FP-Sign': CliCliConfig.fingerPrintSign,
      'X-FP-Algo': CliCliConfig.fingerPrintAlgo,
      'X-App-Id': CliCliConfig.appId,
      'X-Platform': CliCliConfig.platform,
      'X-Timestamp': ts,
      'X-Nonce': nonce,
      'X-Signature': signature,
      'X-Request-Id': _hex(8),
      'X-Session-Id': _sessionId,
      'X-Trace-Id': _hex(16),
      'X-Span-Id': _hex(8),
    };
  }

  Uint8List _encryptJson(Map<String, dynamic> payload) {
    final plain = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
    return _encryptWithKey(_sessionKey, plain);
  }

  Uint8List _encryptWithKey(Uint8List key, List<int> plain) {
    final t = nowSeconds;
    final raw = EsdkV3.deriveCode(key, t);
    final entries = <EsdkZoneEntry>[
      for (final selector in raw.sublist(1))
        EsdkZoneEntry(selector, _randomBytes(kAlgoTable[selector]![1])),
    ];
    return EsdkV3.encrypt(
      key: key,
      plaintext: plain,
      entries: entries,
      timeSeconds: t,
    );
  }

  Map<String, dynamic> _decode(Response<List<int>> response) {
    final status = response.statusCode ?? 0;
    final bytes = response.data ?? const <int>[];
    if (status >= 500) {
      throw MediaSourceException(
        MediaSourceErrorKind.protocol,
        '服务端错误 HTTP $status',
        code: status,
        retryable: true,
      );
    }
    if (bytes.isEmpty) {
      throw MediaSourceException(
        MediaSourceErrorKind.protocol,
        '空响应 HTTP $status',
        code: status,
        retryable: true,
      );
    }
    final encrypted =
        response.headers.value('x-encrypted') != null ||
        (response.headers.value('content-type') ?? '').contains(
          'application/octet-stream',
        );
    final text = utf8.decode(bytes, allowMalformed: true);
    if (encrypted || !_looksLikeJson(text)) {
      final clear = _decrypt(bytes);
      return _parseJson(clear);
    }
    return _parseJson(bytes);
  }

  Uint8List _decrypt(List<int> wire) {
    try {
      return EsdkV3.decrypt(
        key: _sessionKey,
        wire: wire,
        codeSalt: ascii.encode(CliCliConfig.serverCodeSalt),
      );
    } on StateError catch (error) {
      throw MediaSourceException(
        MediaSourceErrorKind.protocol,
        '响应解密失败：${error.message}',
        retryable: true,
        cause: error,
      );
    }
  }

  Map<String, dynamic> _parseJson(List<int> bytes) {
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      throw const FormatException('root is not an object');
    } on FormatException catch (error) {
      throw MediaSourceException(
        MediaSourceErrorKind.protocol,
        '响应不是合法 JSON：${error.message}',
        retryable: true,
        cause: error,
      );
    }
  }

  bool _looksLikeJson(String text) {
    final trimmed = text.trimLeft();
    return trimmed.startsWith('{') || trimmed.startsWith('[');
  }

  void _applyTimestamp(Map<String, dynamic> json) {
    final serverMs = _asInt(json['timestamp']);
    if (serverMs == null || serverMs <= 0) return;
    final localMs = DateTime.now().millisecondsSinceEpoch;
    final offset = serverMs / 1000.0 - localMs / 1000.0;
    if (offset.abs() > 3) {
      _timeOffsetSeconds = offset;
    }
    _timeSynced = true;
  }

  // -------------------------------------------------------------- negotiate

  Future<void> _doNegotiate() async {
    if (!_timeSynced) {
      await _syncTimeProbe();
    }
    final key = _deviceSecretKey();
    final plain = utf8.encode(
      jsonEncode(<String, String>{
        'deviceId': CliCliConfig.deviceId,
        'platform': CliCliConfig.platform,
      }),
    );
    final wire = _encryptWithKey(key, plain);
    final response = await _post(
      CliCliConfig.pathNegotiate,
      wire,
      overrideHeaders: _headers(encrypted: true),
    );
    final bytes = response.data ?? const <int>[];
    if (bytes.isEmpty) {
      throw const MediaSourceException(
        MediaSourceErrorKind.protocol,
        '会话协商返回空响应',
        retryable: true,
      );
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    Map<String, dynamic> json;
    if (_looksLikeJson(text)) {
      json = _parseJson(bytes);
    } else {
      json = _parseJson(
        EsdkV3.decrypt(
          key: key,
          wire: bytes,
          codeSalt: ascii.encode(CliCliConfig.serverCodeSalt),
        ),
      );
    }
    final code = _asInt(json['code']);
    if (code != null && code != 0 && code != 200) {
      throw _apiError(code, _asString(json['msg']));
    }
    final data = json['data'];
    if (data is Map) {
      final secret = _asString(data['deviceSecret']);
      if (secret.isNotEmpty) {
        _sessionSecret = secret;
        _negotiated = true;
      }
      final version = _asInt(data['keyVersion']);
      if (version != null && version > 0) _keyVersion = version;
    }
    final serverTime = _asInt(json['serverTime']);
    if (serverTime != null && serverTime > 0) {
      _timeOffsetSeconds =
          serverTime / 1000.0 - DateTime.now().millisecondsSinceEpoch / 1000.0;
      _timeSynced = true;
    }
  }

  Uint8List _deviceSecretKey() {
    final digest = c.Hmac(
      c.sha256,
      ascii.encode(CliCliConfig.masterSecret),
    ).convert(utf8.encode('device:${CliCliConfig.deviceId}'));
    return Uint8List.fromList(ascii.encode(digest.toString()));
  }

  Future<void> _syncTimeProbe() async {
    try {
      final response = await _post(
        CliCliConfig.pathHome,
        _encryptJson(<String, dynamic>{
          'categoryId': '',
          'tags': <String>[],
          'pageIndex': 1,
          'pageSize': 1,
          'videoId': '',
        }),
      );
      final json = _decode(response);
      _applyTimestamp(json);
    } catch (_) {
      // A 4020 response still carries `timestamp`; _decode applied it already.
    } finally {
      _timeSynced = true;
    }
  }

  Future<void> _recoverSession() async {
    if (!_timeSynced) {
      await _syncTimeProbe();
    }
    await negotiate();
  }

  // ---------------------------------------------------------------- helpers

  Uint8List _randomBytes(int length) {
    final out = Uint8List(length);
    for (var i = 0; i < length; i++) {
      out[i] = _random.nextInt(256);
    }
    return out;
  }

  String _hex(int byteCount) {
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  MediaSourceException _apiError(int code, String message) {
    final kind = switch (code) {
      4032 => MediaSourceErrorKind.vipRequired,
      4031 => MediaSourceErrorKind.adRequired,
      4012 || 4013 || 401 => MediaSourceErrorKind.authentication,
      404 => MediaSourceErrorKind.notFound,
      4020 => MediaSourceErrorKind.protocol,
      _ => MediaSourceErrorKind.protocol,
    };
    return MediaSourceException(
      kind,
      message.isEmpty ? '接口错误 $code' : message,
      code: code,
      retryable: code == 4020 || code >= 500,
    );
  }

  String _networkMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout => '连接超时',
      DioExceptionType.receiveTimeout => '响应超时',
      DioExceptionType.sendTimeout => '发送超时',
      DioExceptionType.connectionError => '网络不可达',
      DioExceptionType.badCertificate => '证书校验失败',
      DioExceptionType.cancel => '请求已取消',
      _ => error.message ?? '网络错误',
    };
  }
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String _asString(Object? value) {
  if (value == null) return '';
  return value is String ? value : value.toString();
}
