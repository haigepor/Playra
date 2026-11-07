import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'primitives.dart';
import 'response_backend.dart';

const _coreAsset = 'package:lumina_engine/core_shim';
@Native<Int Function()>(symbol: 'lumina_core_abi_version', assetId: _coreAsset)
external int _abiVersion();
@Native<
  Int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Uint8>, Pointer<Uint8>)
>(symbol: 'lumina_core_init', assetId: _coreAsset)
external int _initialize(
  Pointer<Utf8> library,
  Pointer<Utf8> json,
  Pointer<Uint8> key,
  Pointer<Uint8> iv,
);
@Native<
  Int Function(
    Pointer<Uint8>,
    Size,
    Uint32,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
  )
>(symbol: 'lumina_core_call', assetId: _coreAsset)
external int _exchange(
  Pointer<Uint8> json,
  int length,
  int timeoutMs,
  Pointer<Pointer<Uint8>> output,
  Pointer<Size> outputLength,
);
@Native<Void Function(Pointer<Void>)>(
  symbol: 'lumina_core_free',
  assetId: _coreAsset,
)
external void _release(Pointer<Void> pointer);

/// 同进程 C 适配层持有回调；Dart 不接收来自原生线程的回调，也不运行 Python。
class CoreResponseBackend implements LuminaResponseBackend {
  CoreResponseBackend._();
  static bool get supported =>
      Platform.isAndroid && Abi.current() == Abi.androidArm64;

  /// 通道常量缺失时不要尝试原生加速：init 抛出的类型错误会打死整个 worker，
  /// 而 auto 模式本可安静回落到 _fuse。profile 精简版据此跳过 core。
  static bool configured(Map<String, dynamic> profile) {
    bool hex16(Object? value) =>
        value is String && RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(value);
    final tcp = profile['_CORE_TCP'];
    return hex16(profile['_CORE_CHANNEL_KEY']) &&
        hex16(profile['_CORE_CHANNEL_IV']) &&
        tcp is String &&
        tcp.isNotEmpty &&
        tcp.length <= 128 &&
        tcp.contains(':');
  }
  late final String version;
  static CoreResponseBackend open(
    Map<String, dynamic> profile,
    String fingerprint,
    String filesPath,
  ) {
    if (!supported)
      throw const ResponseBackendFailure('CORE_UNSUPPORTED', terminal: true);
    if (!configured(profile))
      throw const ResponseBackendFailure('CORE_CONFIG');
    try {
      if (_abiVersion() != 1)
        throw const ResponseBackendFailure('CORE_ABI', terminal: true);
      using((arena) {
        Pointer<Uint8> bytes(String field) {
          final data = hexBytes(profile[field]);
          if (data.length != 16)
            throw const ResponseBackendFailure('CORE_CONFIG', terminal: true);
          final pointer = arena<Uint8>(16);
          pointer.asTypedList(16).setAll(0, data);
          return pointer;
        }

        final config = jsonEncode({
          'app_id': '${profile['APP_ID']}',
          'device_id': fingerprint,
          'code_version': profile['CODE_VERSION'],
          'app_version': profile['APP_VERSION'],
          'files_path': filesPath,
          'tcp': profile['_CORE_TCP'],
        });
        _check(
          _initialize(
            nullptr,
            config.toNativeUtf8(allocator: arena),
            bytes('_CORE_CHANNEL_KEY'),
            bytes('_CORE_CHANNEL_IV'),
          ),
        );
      });
      final backend = CoreResponseBackend._();
      final reply = backend._call({
        'action': 'get_version',
        'payload': {},
      }, const Duration(seconds: 20));
      final payload = reply['payload'];
      final value = payload is Map ? payload['version'] : null;
      if ((value is! String && value is! int) ||
          '$value'.isEmpty ||
          '$value'.length > 128) {
        throw const ResponseBackendFailure('CORE_VERSION', terminal: true);
      }
      backend.version = '$value';
      return backend;
    } on ArgumentError {
      throw const ResponseBackendFailure('CORE_LOAD', terminal: true);
    }
  }

  static void _check(int code) {
    if (code == 0) return;
    final name = switch (code) {
      -1 => 'CORE_ARGUMENT',
      -2 => 'CORE_LOAD',
      -3 => 'CORE_SYMBOL',
      -4 => 'CORE_SELFTEST',
      -5 => 'CORE_NOT_READY',
      -6 => 'CORE_TIMEOUT',
      -7 => 'CORE_QUARANTINED',
      -8 => 'CORE_REPLY',
      -9 => 'CORE_MEMORY',
      -10 => 'CORE_THREAD',
      -11 => 'CORE_PAGE_SIZE',
      -12 => 'CORE_IDENTITY',
      -13 => 'CORE_BUSY',
      _ => 'CORE_ERROR',
    };
    throw ResponseBackendFailure(
      name,
      terminal: code != -8 && code != -1 && code != -13,
    );
  }

  Map<String, dynamic> _call(Map<String, dynamic> action, Duration budget) {
    final input = utf8.encode(jsonEncode(action));
    try {
      return using((arena) {
        final pointer = arena<Uint8>(input.length);
        pointer.asTypedList(input.length).setAll(0, input);
        final output = arena<Pointer<Uint8>>(), length = arena<Size>();
        _check(
          _exchange(
            pointer,
            input.length,
            budget.inMilliseconds.clamp(1, 30000),
            output,
            length,
          ),
        );
        try {
          if (output.value == nullptr ||
              length.value <= 0 ||
              length.value > 8 * 1024 * 1024) {
            throw const ResponseBackendFailure('CORE_REPLY');
          }
          final reply = jsonDecode(
            utf8.decode(output.value.asTypedList(length.value)),
          );
          if (reply is! Map<String, dynamic> || reply['code'] != 200) {
            throw const ResponseBackendFailure('CORE_REPLY');
          }
          return reply;
        } finally {
          if (output.value != nullptr) _release(output.value.cast());
        }
      });
    } on FormatException {
      throw const ResponseBackendFailure('CORE_REPLY');
    }
  }

  @override
  Uint8List decrypt(Uint8List raw, String path, Duration budget) {
    final callBudget = Duration(
      milliseconds: (budget.inMilliseconds ~/ 4).clamp(100, 1500),
    );
    final reply = _call({
      'action': 'api_decrypt',
      'payload': {'data': utf8.decode(raw), 'path': path},
    }, callBudget);
    final payload = reply['payload'];
    final data = payload is Map ? payload['data'] : null;
    if (data is! String) throw const ResponseBackendFailure('CORE_REPLY');
    return Uint8List.fromList(utf8.encode(data));
  }
}
