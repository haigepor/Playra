import 'dart:ffi';
import 'dart:convert';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'primitives.dart';

const _asset = 'package:lumina_engine/engine';
@Native<Int Function(Pointer<Utf8>)>(symbol: 'lumafuse_init', assetId: _asset)
external int _init(Pointer<Utf8> path);
@Native<Int Function()>(symbol: 'lumafuse_post_init', assetId: _asset)
external int _postInit();
@Native<Pointer<Utf8> Function()>(symbol: 'lumafuse_version', assetId: _asset)
external Pointer<Utf8> _version();
@Native<
  Long Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Uint64,
  )
>(symbol: 'lumafuse_encrypt_iv', assetId: _asset)
external int _encrypt(
  Pointer<Uint8> key,
  Pointer<Uint8> iv,
  Pointer<Uint8> data,
  int length,
  Pointer<Uint8> out,
  int capacity,
);
@Native<
  Long Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Uint64,
  )
>(symbol: 'lumafuse_encrypt_a1', assetId: _asset)
external int _auth(
  Pointer<Uint8> key,
  Pointer<Uint8> iv,
  Pointer<Uint8> data,
  int length,
  Pointer<Uint8> out,
  int capacity,
);
@Native<Long Function(Pointer<Uint8>, Uint64, Pointer<Uint8>, Pointer<Uint8>)>(
  symbol: 'lumafuse_calib_direct',
  assetId: _asset,
)
external int _calibrate(
  Pointer<Uint8> key,
  int blocks,
  Pointer<Uint8> constants,
  Pointer<Uint8> tweaks,
);
@Native<
  Int Function(
    Pointer<Uint8>,
    Uint64,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
  )
>(symbol: 'lumafuse_decrypt', assetId: _asset)
external int _decrypt(
  Pointer<Uint8> cipher,
  int blocks,
  Pointer<Uint8> key,
  Pointer<Uint8> c,
  Pointer<Uint8> constants,
  Pointer<Uint8> tweaks,
  Pointer<Uint8> out,
);

/// C 库含全局状态：只允许一个长驻 worker 使用，调用同步完成后才释放内存。
class LuminaEngine {
  LuminaEngine(String imagePath, {this.trace}) {
    using((arena) {
      if (_init(imagePath.toNativeUtf8(allocator: arena)) != 0 ||
          _postInit() != 0) {
        throw StateError('ENGINE_INIT_ERROR');
      }
    });
    version = _version().toDartString();
  }
  late final String version;
  final void Function(String stage, int micros)? trace;

  /// Cb 生成器在约 1944 块之后会 abort 或挂死宿主进程（不是抛异常，接不住）。
  /// 服务端分页上限（列表 ≤25 / 搜索 ≤30 / 评论 ≤50）保证正常响应远低于此；
  /// 超限时由调用方在进入原生层之前拒绝。
  static const maxBlocks = 1900;
  final _calibrations =
      <String, ({Uint8List c, Uint8List constants, Uint8List tweaks})>{};
  int _calibrationBytes = 0;
  void clearCalibrationCache() {
    _calibrations.clear();
    _calibrationBytes = 0;
  }

  Pointer<Uint8> _copy(Arena arena, List<int> value) {
    final p = arena<Uint8>(value.length);
    p.asTypedList(value.length).setAll(0, value);
    return p;
  }

  Uint8List encrypt(List<int> key, List<int> data, {List<int>? iv}) {
    if (key.length != 16 || data.isEmpty || data.length % 16 != 0)
      throw const FormatException('Block input');
    final result = _run(key, iv ?? key.reversed.toList(), data, false);
    // 1.6 引擎额外输出一个填充块；SDK EBlock 仅消费已填充输入对应的块。
    if (result.length < data.length) throw StateError('ENGINE_TRUNCATED');
    return Uint8List.fromList(result.sublist(0, data.length));
  }

  Uint8List auth(List<int> key, List<int> iv, List<int> a1) {
    if (key.length != 32 || iv.length != 16 || a1.length != 104)
      throw const FormatException('Auth input');
    final result = _run(key, iv, a1, true);
    if (result.length != 112) throw StateError('ENGINE_AUTH_ERROR');
    return result;
  }

  Uint8List _run(List<int> key, List<int> iv, List<int> data, bool auth) =>
      using((arena) {
        if (iv.length != 16) throw const FormatException('IV length');
        final capacity = data.length + 64, out = arena<Uint8>(data.length + 64);
        final count = (auth ? _auth : _encrypt)(
          _copy(arena, key),
          _copy(arena, iv),
          _copy(arena, data),
          data.length,
          out,
          capacity,
        );
        if (count < 0 || count > capacity)
          throw StateError('ENGINE_ENCRYPT_ERROR rc=$count capacity=$capacity');
        return Uint8List.fromList(out.asTypedList(count));
      });
  Uint8List decrypt(List<int> key, List<int> cipher) {
    if (key.length != 16 ||
        cipher.isEmpty ||
        cipher.length % 16 != 0 ||
        cipher.length > 2 * 1024 * 1024)
      throw const FormatException('Cipher length');
    if (cipher.length ~/ 16 > maxBlocks) throw StateError('ENGINE_BLOCK_LIMIT');
    final cacheKey = base64Encode(key);
    var calibration = _calibrations.remove(cacheKey);
    if (calibration != null) {
      _calibrationBytes -= calibration.constants.length * 2;
    }
    if (calibration == null || calibration.constants.length < cipher.length) {
      final clock = Stopwatch()..start();
      // 与 EBlock.calibrate 一致：一次 C 调用标定整链，不做逐块 FFI 往返。
      final c = xor(
        encrypt(key, List.filled(16, 0), iv: List.filled(16, 0)).sublist(0, 16),
        Aes128(key).f(List.filled(16, 0)),
      );
      calibration = using((arena) {
        final constants = arena<Uint8>(cipher.length);
        final tweaks = arena<Uint8>(cipher.length);
        final blocks = cipher.length ~/ 16;
        if (_calibrate(_copy(arena, key), blocks, constants, tweaks) !=
            blocks) {
          throw StateError('ENGINE_CALIBRATION_ERROR');
        }
        return (
          c: Uint8List.fromList(c),
          constants: Uint8List.fromList(constants.asTypedList(cipher.length)),
          tweaks: Uint8List.fromList(tweaks.asTypedList(cipher.length)),
        );
      });
      trace?.call('calibration', clock.elapsedMicroseconds);
    } else {
      trace?.call('calibration_hit', 0);
    }
    // fresh-K 不会命中；缓存仅复用同 K 的已覆盖前缀，并限制总内存和密钥数。
    final prepared = calibration!;
    final bytes = prepared.constants.length * 2;
    if (bytes <= 2 * 1024 * 1024) {
      while (_calibrations.isNotEmpty &&
          (_calibrations.length >= 8 ||
              _calibrationBytes + bytes > 2 * 1024 * 1024)) {
        final evicted = _calibrations.remove(_calibrations.keys.first)!;
        _calibrationBytes -= evicted.constants.length * 2;
      }
      _calibrations[cacheKey] = prepared;
      _calibrationBytes += bytes;
    }
    return using((arena) {
      final blocks = cipher.length ~/ 16, k = _copy(arena, key);
      final out = arena<Uint8>(cipher.length + 16);
      final clock = Stopwatch()..start();
      if (_decrypt(
            _copy(arena, cipher),
            blocks,
            k,
            _copy(arena, prepared.c),
            _copy(arena, prepared.constants),
            _copy(arena, prepared.tweaks),
            out,
          ) !=
          0)
        throw StateError('ENGINE_DECRYPT_ERROR');
      trace?.call('decrypt_chain', clock.elapsedMicroseconds);
      return unpad(out.asTypedList(cipher.length));
    });
  }
}
