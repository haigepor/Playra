/// CENC 内容密钥推导（对标 openhongguo internal/drm/spade.go）。
///
/// 服务端在 encrypt_info.spade_a 里携带包装密钥材料；官方播放器把它
/// base64 解码、做固定置换、拆出十六进制内容密钥与方案版本。
/// 本实现与其行为兼容；纯本地计算，不再发任何请求。
library;

import 'dart:convert';

class HongguoDerivedKey {
  const HongguoDerivedKey({required this.hex, required this.version});

  /// AES 内容密钥（小写十六进制）。
  final String hex;
  final String version;
}

class HongguoKeyMaterialError implements Exception {
  const HongguoKeyMaterialError(this.message);
  final String message;
  @override
  String toString() => 'hongguo key material: $message';
}

/// 从 base64 的 spade_a 还原内容密钥。
HongguoDerivedKey deriveHongguoContentKey(String spadeA) {
  List<int> raw;
  try {
    raw = _b64Decode(spadeA.trim());
  } catch (_) {
    throw const HongguoKeyMaterialError('unrecognized key material');
  }
  if (raw.length < 4) {
    throw const HongguoKeyMaterialError('unrecognized key material');
  }
  final marker = raw[0] ^ raw[1] ^ raw[2];
  final prefixLen = marker - 0x30;
  if (prefixLen < 1 || prefixLen > raw.length) {
    throw const HongguoKeyMaterialError('unrecognized key material');
  }
  final outLen = raw.length - marker + 0x2f;
  if (outLen < 2 || 1 + outLen > raw.length) {
    throw const HongguoKeyMaterialError('unrecognized key material');
  }
  final buf = raw.sublist(1, 1 + outLen);

  // marker 字节是尾部窗口前两字节与窗口所有字节的异或。
  final tail = raw.length - prefixLen;
  if (tail - 2 < 0 || tail > raw.length) {
    throw const HongguoKeyMaterialError('unrecognized key material');
  }
  final b16 = raw[tail - 2], b14 = raw[tail - 1];
  final tag = List<int>.generate(
    prefixLen,
    (i) {
      if (i + tail >= raw.length) {
        throw const HongguoKeyMaterialError('unrecognized key material');
      }
      return b14 ^ b16 ^ raw[i + tail];
    },
  );
  final tagText = String.fromCharCodes(tag);
  _scramble(
    buf,
    tagText.startsWith('app_v2') || tagText.startsWith('web_v2'),
  );

  final versionLen = _hexDigit(buf[0]);
  if (versionLen < 1 || versionLen >= outLen) {
    throw const HongguoKeyMaterialError('unrecognized key material');
  }
  final keyLen = outLen - versionLen;
  final hexKey = String.fromCharCodes(buf.sublist(1, keyLen));
  if (hexKey.isEmpty || hexKey.length % 2 != 0) {
    throw const HongguoKeyMaterialError('unrecognized key material');
  }
  for (var i = 0; i < hexKey.length; i++) {
    if (_hexDigit(hexKey.codeUnitAt(i)) < 0) {
      throw const HongguoKeyMaterialError('unrecognized key material');
    }
  }
  return HongguoDerivedKey(
    hex: hexKey.toLowerCase(),
    version: String.fromCharCodes(buf.sublist(keyLen)),
  );
}

void _scramble(List<int> buf, bool v2) {
  if (v2) {
    final last = buf.length - 1;
    for (var i = 0; i + 1 < buf.length; i += 2) {
      final t = buf[i];
      buf[i] = buf[i + 1];
      buf[i + 1] = t;
      if (i == last - 2) break;
    }
  }
  var prev = 0x55, cur = 0xfa;
  for (var i = 0; i < buf.length; i++) {
    final b = buf[i];
    final term = -(0x15 + _popcount(i));
    if (i % 2 == 0) {
      buf[i] = _byte8(v2 ? (cur ^ b) - prev + term : term + (cur ^ b));
      cur = b;
    } else {
      buf[i] = _byte8(v2 ? (prev ^ b) - prev + term : term + (prev ^ b));
      prev = b;
    }
  }
}

/// 按位计数（对应官方播放器 NEON 的字节两两相加）。
int _popcount(int v) => _bits8(v & 0xFF) + _bits8((v >> 8) & 0xFF);

int _bits8(int v) {
  var n = 0;
  while (v != 0) {
    v &= v - 1;
    n++;
  }
  return n;
}

int _hexDigit(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  return -1;
}

/// Go byte 语义：截断到 8 位（补码回绕）。
int _byte8(int v) => v & 0xFF;

List<int> _b64Decode(String s) => base64Decode(s);
