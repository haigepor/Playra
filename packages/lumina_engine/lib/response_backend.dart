import 'dart:typed_data';

class ResponseBackendFailure implements Exception {
  const ResponseBackendFailure(this.code, {this.terminal = false});
  final String code;
  final bool terminal;
  @override
  String toString() => code;
}

abstract interface class LuminaResponseBackend {
  Uint8List decrypt(Uint8List raw, String path, Duration budget);
}

/// 路由只处理已识别的后端错误；协议数据损坏继续由原解密路径严格验证。
class ResponseRouter {
  ResponseRouter(this.preferred, {this.strict = false});
  final LuminaResponseBackend? preferred;
  final bool strict;
  String? _disabledReason;

  ({Uint8List plain, String backend, String? fallback}) decode(
    Uint8List raw,
    String path,
    Duration budget,
    Uint8List Function() fallback,
  ) {
    final backend = preferred;
    if (backend != null && _disabledReason == null) {
      try {
        return (
          plain: backend.decrypt(raw, path, budget),
          backend: 'core',
          fallback: null,
        );
      } on ResponseBackendFailure catch (error) {
        if (error.terminal) _disabledReason = error.code;
        if (strict) rethrow;
        return (plain: fallback(), backend: 'fuse', fallback: error.code);
      }
    }
    if (strict) {
      throw ResponseBackendFailure(
        _disabledReason ?? 'CORE_UNAVAILABLE',
        terminal: true,
      );
    }
    return (plain: fallback(), backend: 'fuse', fallback: _disabledReason);
  }
}
