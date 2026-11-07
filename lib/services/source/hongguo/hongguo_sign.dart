/// 红果短剧匿名协议的签名栈。
///
/// 从 openhongguo（github.com/beilunyang/openhongguo，Apache-2.0）
/// 的 internal/protocol/sign 逐文件移植为纯 Dart；期望输出以 Go 侧
/// sign_test.go 的固定向量为准（见 test/hongguo_sign_test.dart）。
/// 本文件刻意不依赖 Flutter，可直接 `dart run` 验证。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

const int _u32Mask = 0xFFFFFFFF;

int _u32(int x) => x & _u32Mask;

int _rol32(int value, int count) {
  final n = count & 31;
  if (n == 0) return _u32(value);
  return _u32((_u32(value) << n) | (_u32(value) >>> (32 - n)));
}

int _ror32(int value, int count) {
  final n = count & 31;
  if (n == 0) return _u32(value);
  return _u32((_u32(value) >>> n) | (_u32(value) << (32 - n)));
}

/// 64 位循环右移。Dart VM int 即 64 位补码，位型与 Go uint64 一致。
int _ror64(int value, int count) {
  final n = count & 63;
  if (n == 0) return value;
  return (value >>> n) | (value << (64 - n));
}

int _reverseBits(int value) {
  var result = 0;
  for (var i = 0; i < 8; i++) {
    result = (result << 1) | ((value >> i) & 1);
  }
  return result;
}

int _zigzag(int value) => (value << 1) ^ (value >> 63);

Uint8List _le32(int value) {
  final b = ByteData(4)..setUint32(0, _u32(value), Endian.little);
  return b.buffer.asUint8List();
}

Uint8List _be32(int value) {
  final b = ByteData(4)..setUint32(0, _u32(value), Endian.big);
  return b.buffer.asUint8List();
}

Uint8List _le64(int value) {
  final b = ByteData(8)..setUint64(0, value, Endian.little);
  return b.buffer.asUint8List();
}

ByteData _bd(List<int> data) =>
    ByteData.sublistView(Uint8List.fromList(data));

int _readLe64(List<int> data, int offset) =>
    _bd(data.sublist(offset, offset + 8)).getUint64(0, Endian.little);

int _readLe32(List<int> data, int offset) =>
    _bd(data.sublist(offset, offset + 4)).getUint32(0, Endian.little);

Uint8List _md5Raw(List<int> value) =>
    Uint8List.fromList(crypto.md5.convert(value).bytes);

/// GM/T 0004-2012 SM3。`abc` 的摘要即为公开测试向量。
Uint8List sm3Sum(List<int> msg) {
  var h = <int>[
    0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600, //
    0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
  ];
  final padded = _sm3Pad(msg);
  final w = List<int>.filled(68, 0);
  final wp = List<int>.filled(64, 0);
  for (var off = 0; off < padded.length; off += 64) {
    final block = padded.sublist(off, off + 64);
    for (var i = 0; i < 16; i++) {
      w[i] = _readBe32(block, i * 4);
    }
    for (var j = 16; j < 68; j++) {
      final x = w[j - 16] ^ w[j - 9] ^ _rol32(w[j - 3], 15);
      w[j] = _sm3P1(x) ^ _rol32(w[j - 13], 7) ^ w[j - 6];
    }
    for (var j = 0; j < 64; j++) {
      wp[j] = w[j] ^ w[j + 4];
    }
    var a = h[0], b = h[1], c = h[2], d = h[3];
    var e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var j = 0; j < 64; j++) {
      final tj = j < 16 ? 0x79cc4519 : 0x7a879d8a;
      final ss1 = _rol32(_u32(_rol32(a, 12) + e + _rol32(tj, j)), 7);
      final ss2 = ss1 ^ _rol32(a, 12);
      final tt1 = _u32(_sm3FF(j, a, b, c) + d + ss2 + wp[j]);
      final tt2 = _u32(_sm3GG(j, e, f, g) + hh + ss1 + w[j]);
      d = c;
      c = _rol32(b, 9);
      b = a;
      a = tt1;
      hh = g;
      g = _rol32(f, 19);
      f = e;
      e = _sm3P0(tt2);
    }
    h = [
      h[0] ^ a, h[1] ^ b, h[2] ^ c, h[3] ^ d, //
      h[4] ^ e, h[5] ^ f, h[6] ^ g, h[7] ^ hh,
    ];
  }
  final out = Uint8List(32);
  for (var i = 0; i < 8; i++) {
    final b = ByteData(4)..setUint32(0, _u32(h[i]), Endian.big);
    out.setRange(i * 4, i * 4 + 4, b.buffer.asUint8List());
  }
  return out;
}

int _readBe32(List<int> data, int offset) =>
    _bd(data.sublist(offset, offset + 4)).getUint32(0, Endian.big);

Uint8List _sm3Pad(List<int> msg) {
  final bitLen = msg.length * 8;
  final out = BytesBuilder();
  out.add(msg);
  out.addByte(0x80);
  while ((out.length + 8) % 64 != 0) {
    out.addByte(0);
  }
  out.add(_be64(bitLen));
  return out.toBytes();
}

Uint8List _be64(int value) {
  final b = ByteData(8)..setUint64(0, value, Endian.big);
  return b.buffer.asUint8List();
}

int _sm3FF(int j, int x, int y, int z) {
  if (j < 16) return x ^ y ^ z;
  return (x & y) | (x & z) | (y & z);
}

int _sm3GG(int j, int x, int y, int z) {
  if (j < 16) return x ^ y ^ z;
  return (x & y) | ((~x & _u32Mask) & z);
}

int _sm3P0(int x) => x ^ _rol32(x, 9) ^ _rol32(x, 17);
int _sm3P1(int x) => x ^ _rol32(x, 15) ^ _rol32(x, 23);

// ---------------------------------------------------------------------------
// 常量（sign/const.go）
// ---------------------------------------------------------------------------

const int gorgonSDKVersion = 67503104;
const String signAppID = '8662';
const String signChannelID = '1588093228';

final Uint8List _sboxBytes = () {
  const b64 =
      '+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw==';
  return Uint8List.fromList(base64Decode(b64));
}();

final Uint8List _branch2Orders = () {
  const hexStr =
      '0f0704000908030a060b050d0e010c020f05080c0009020103070e060b0a0d04060500070c000a04080f010b0d09020e060b02050403080101070a000d0c090e0d070e0f0b0208030c0509010004060a0d0902060f0b0a040807000c0503010e0c090f07060f030e020d0405010b0a000c050a090e0802040407030f01060b000b0f0408020a0700090d06010e03050c0b060a0508020c03070f0e090d0001040906080f050800040a0b030d01020c0e090d0c0604070a03030f00080105020e01000d0f090a0b0e0402080703060c0501080a0c0f0905060b000304020e070d04080f000c0f0e0d0a01060207090503040205080d0b0a0606000e0f070c09030a08040f000b01060d0c0709030e05020a070b050f00020e0108030d0c0609040d070f08050f06040b0a0e0c090002030d0c020704010b0e0e08060f09050003';
  return Uint8List.fromList(_decodeHex(hexStr));
}();

final Uint8List _medusaSignKey = Uint8List.fromList(
  _decodeHex('8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eaef71cb691f7aa8aa2f5'),
);
final Uint8List _medusaAESKey = Uint8List.fromList(
  _decodeHex('f1593376766ea98d34f31b057a9d5be4'),
);
final Uint8List _medusaAESIV = Uint8List.fromList(
  _decodeHex('1fe109a4125283f418de9e051a969e12'),
);

final List<int> _branch2SV = <int>[
  0xa7aefe20, 0x7149f1d6, 0x47e4ca07, 0xe9b58f67, 0x93b924de, 0xc614d0f5, 0x38afe0ef, 0xb2bbad73,
  0xe24444c3, 0x9d3aec9b, 0xdf7b37e4, 0xd8b16d40, 0xf8ac31b8, 0x76b9a90b, 0x31d833ee, 0x953fce64,
  0x353595a4, 0x4609c13b, 0x36925008, 0x8c6d0925, 0x5df5c177, 0x1cfbf52b, 0x8a4fa7f0, 0x114ca35e,
  0x8193f984, 0x7a7a8733, 0x316ab4d5, 0x3c20cfc9, 0xa6d84453, 0x3a18500c, 0x798ec47a, 0x97a76b28,
  0x66c4ff96, 0x51716443, 0x0dd2fc3b, 0xb5696da7, 0xbbeb3ac5, 0x5c53d204, 0xd32608ce, 0x7279b9ec,
  0xf4188ecf, 0xf7d793db, 0x332cc491, 0xab76ae15, 0x9bebe727, 0x18a01384, 0x5be9f8a7, 0x5f90a754,
  0x39b663c0, 0x36673c83, 0x7c92f514, 0x9d7d94d7, 0xe2e8d9aa, 0x5f7e9ea9, 0x7abd4551, 0x569e05da,
  0x40a25632, 0x3df5a9a5, 0xbab37d80, 0x454286dc, 0x3f5d4e78, 0x03d7b75d, 0xb1fe4af7, 0xa5ab26a3,
];

Uint8List _decodeHex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

// ---------------------------------------------------------------------------
// prim（sign/prim.go）
// ---------------------------------------------------------------------------

int _getIV(int iv, List<int> data) {
  var value = _u32(iv);
  for (var i = 0; i < data.length; i++) {
    final b = data[i];
    if (i & 1 == 0) {
      value = _u32((value >> 4) ^ value ^ (value << 6) ^ b);
      continue;
    }
    final inner = _u32((value >> 7) ^ value ^ (b | (value << 12)));
    value = _u32(~inner);
  }
  return value;
}

int _sumMD5(List<int> data) {
  var check = 0x20220420;
  for (var i = 0; i < 12; i++) {
    int temp;
    if (i & 1 == 0) {
      temp = (check >> 3) ^ check;
      check = _u32(data[i] ^ (check << 7));
    } else {
      temp = (check >> 5) ^ check;
      check = _u32(data[i] | (check << 11));
      check = _u32(~check);
    }
    check ^= temp;
  }
  return _u32((check | 4) ^ 0x01000000);
}

// ---------------------------------------------------------------------------
// gorgon（sign/gorgon.go）
// ---------------------------------------------------------------------------

Uint8List _rc4Gorgon(List<int> data, List<int> key) {
  final s = Uint8List(256);
  for (var i = 0; i < 256; i++) {
    s[i] = i;
  }
  var j = 0;
  // 注意：该变体的 KSA 只做单赋值（s[i] = s[j]），不是标准 RC4 的交换。
  for (var i = 0; i < 256; i++) {
    j = (j + s[i] + key[i % key.length]) & 255;
    s[i] = s[j];
  }
  final out = Uint8List(data.length);
  var i = 0, jj = 0;
  for (var k = 0; k < data.length; k++) {
    i++;
    final x = s[i & 255];
    jj = _u32(jj + x) & 255;
    final y = s[jj];
    s[i & 255] = y;
    out[k] = data[k] ^ s[(y + y) & 255];
  }
  return out;
}

String xGorgon(String query, List<int>? body, bool hasBody, int khronos, int random) {
  final queryMD5 = _md5Raw(utf8.encode(query));
  final bodyMD5 = hasBody ? _md5Raw(body!) : Uint8List(16);
  final input = BytesBuilder();
  input.add(queryMD5.sublist(0, 4));
  input.add(bodyMD5.sublist(0, 4));
  input.add([0, 0, 0, 0]);
  input.add(_le32(gorgonSDKVersion));
  input.add(_be32(khronos));
  final key = [
    0x4a, 0x40, 0x16, (random >> 8) & 255, //
    0x47, 0x6c, 0x01, random & 255,
  ];
  final out = _rc4Gorgon(input.toBytes(), key);
  final n = out.length;
  for (var i = 0; i < n; i++) {
    final value = out[i];
    final swapped = (value >> 4) | ((value << 4) & 0xFF);
    var next = out[0];
    if (i + 1 < n) next = out[i + 1];
    out[i] = _u32(~(_reverseBits(next ^ swapped) ^ 20)) & 0xFF;
  }
  final result = BytesBuilder();
  result.add([0x84, 0x04, random & 255, (random >> 8) & 255, 0x40, 0x01]);
  result.add(out);
  return hexEncode(result.toBytes());
}

String hexEncode(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

// ---------------------------------------------------------------------------
// helios（sign/helios.go）
// ---------------------------------------------------------------------------

String assembleHelios(int khronos, int random) {
  final seed = BytesBuilder();
  seed.add(_le32(random));
  seed.add(utf8.encode(signAppID));
  final digest = _md5Raw(seed.toBytes());
  final ascii = utf8.encode(hexEncode(digest));
  final words = List<int>.generate(4, (i) => _readLe64(ascii, i * 8));
  final table = _heliosDiffuse(words);
  final padded = _heliosPad(khronos);
  final output = BytesBuilder();
  for (var off = 0; off < padded.length; off += 16) {
    final chunk = padded.sublist(off, off + 16);
    var a = _readLe64(chunk, 0);
    var b = _readLe64(chunk, 8);
    for (var t = 0; t < 34; t++) {
      b = table[t] ^ _u64add(a, _ror64(b, 8));
      a = b ^ _ror64(a, 61);
    }
    output.add(_le64(a));
    output.add(_le64(b));
  }
  final result = BytesBuilder();
  result.add(_le32(random));
  result.add(output.toBytes());
  return base64Encode(result.toBytes());
}

/// 64 位加法（Dart int 溢出回绕与 Go uint64 位型一致）。
int _u64add(int a, int b) => a + b;

List<int> _heliosDiffuse(List<int> words) {
  final table = <int>[words[0]];
  var b0 = words[0];
  var b8 = words[1];
  final queue = <int>[...words.sublist(2)];
  for (var i = 0; i < 34; i++) {
    var x8 = _u64add(_ror64(b8, 8), b0);
    x8 ^= i;
    queue.add(x8);
    x8 ^= _ror64(b0, 61);
    table.add(x8);
    b0 = x8;
    b8 = queue.removeAt(0);
  }
  return table;
}

Uint8List _heliosPad(int khronos) {
  final text = utf8.encode('$khronos-$signChannelID-$signAppID');
  final fill = 16 - (text.length % 16);
  final size = ((text.length + 1 + 15) ~/ 16) * 16;
  final out = Uint8List(size);
  for (var i = 0; i < size; i++) {
    out[i] = fill;
  }
  out.setRange(0, text.length, text);
  return out;
}

// ---------------------------------------------------------------------------
// proto（sign/proto.go）
// ---------------------------------------------------------------------------

Uint8List _varint(int value) {
  final out = BytesBuilder();
  var v = value;
  while (v > 127) {
    out.addByte((v & 127) | 128);
    v >>= 7;
  }
  out.addByte(v);
  return out.toBytes();
}

Uint8List _protoKey(int tag, int wire) =>
    _varint((tag << 3) | wire);

Uint8List _protoBytes(int tag, List<int> body) {
  if (body.isEmpty) return Uint8List(0);
  final out = BytesBuilder();
  out.add(_protoKey(tag, 2));
  out.add(_varint(body.length));
  out.add(body);
  return out.toBytes();
}

Uint8List _protoString(int tag, String s) =>
    _protoBytes(tag, utf8.encode(s));

Uint8List _protoSInt(int tag, int value) {
  final out = BytesBuilder();
  out.add(_protoKey(tag, 0));
  out.add(_varint(_zigzag(value)));
  return out.toBytes();
}

Uint8List _protoFloat(int tag, double value) {
  final bd = ByteData(4)..setFloat32(0, value, Endian.little);
  final out = BytesBuilder();
  out.add(_protoKey(tag, 5));
  out.add(bd.buffer.asUint8List());
  return out.toBytes();
}

// ---------------------------------------------------------------------------
// f13（sign/f13.go）
// ---------------------------------------------------------------------------

final List<int> _branch0IV = <int>[
  0xc4a78580, 0xb3c0fd39, 0xc58c5686, 0xc9aa3ba7, 0xf5a7adf2, 0x963c2ed1,
];

final List<int> _branch0TT = <int>[
  0xebb64faf, 0x07aadcc2, 0xcf3187bf, 0xe01138ff, 0x6d0bfcff, 0x5a30a3be, 0xb41ad638, 0x34180eb8,
  0xf233eb6f, 0xb1a584cc, 0xccc30dc7, 0x47d1db51, 0xd55653de, 0x70a84fa1, 0x57473c12, 0xf76f0288,
  0x2c077f0a, 0xda0dcad0, 0xfbb86f6c, 0xfdc4cf00, 0x688a020d, 0xe676c6a6, 0x8cd6338b, 0x1a3c8d0e,
  0xcce8b06b, 0x6ad0ed0b, 0xa0522717, 0xdc71ac83, 0x2285db71, 0xd5b4dda6, 0x736f8650, 0x6560306c,
  0x617ce2a6, 0xe423417e, 0x0a40e143, 0x544e4032, 0x88dffb2a, 0x716c1ae0, 0x4c467a88, 0x05b23bb3,
  0xe1d0b866, 0xbaa3dcb8, 0xae3374d3, 0xc3381a50, 0x1702f75b, 0xfe6da368, 0xf0b4cf48, 0x4e0ffbb8,
  0x72aad10d, 0x26c53a3d, 0xf2bce0f6, 0xb4557581, 0x4a257fdd, 0x8c3182a2, 0xab0b3b86, 0x3d5dfb14,
  0x4f103634, 0xd37b52d7, 0x444eff16, 0xeb0a33d1, 0x6ca86f6e, 0x00284ba7, 0x08387cfa, 0x5fb37586,
];

final List<int> _branch0Init = <int>[
  0x7aba4fc8, 0x67166507, 0x6403fa00, 0x340f512f, //
  984304912, 3005047866, 2874125293, 2152413264,
];

final List<List<int>> _branch0Rounds = <List<int>>[
  [101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3],
  [96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4],
  [96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5],
  [99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6],
  [96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4],
  [100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5],
];

int _branchOf(List<int> query, List<int> bodyMD5, List<int> ts) {
  final iv = _getIV(_getIV(_getIV(0x20230928, query), bodyMD5), ts);
  final low = iv & 15;
  return low - ((low * 171) >> 9) * 3;
}

Uint8List _hashF13(
  List<int> querySM3,
  List<int> bodyMD5,
  List<int> ts,
  int khronos,
) {
  final iv = _getIV(_getIV(_getIV(0x20230928, querySM3), bodyMD5), ts);
  final low = iv & 15;
  final ivV0 = (low * 171) >> 9;
  final branch = low - ivV0 * 3;
  if (branch == 2) {
    return _branch2F13(iv, querySM3, bodyMD5, ts, khronos);
  }
  if (branch != 0) {
    final out = BytesBuilder();
    out.add(querySM3.sublist(0, 16));
    out.add(bodyMD5);
    final summed = BytesBuilder();
    summed.add(querySM3);
    summed.add(bodyMD5);
    out.add(_le32(_sumMD5(summed.toBytes())));
    return out.toBytes();
  }
  return _branch0F13(querySM3, bodyMD5, ts, khronos, ivV0);
}

List<int> _expandWords(List<int> data) {
  final di = <int>[];
  for (var off = 0; off + 4 <= data.length; off += 4) {
    di.add(_readBe32(data, off));
  }
  var di0 = di[0];
  for (var i = 0; i < 112; i++) {
    final di1 = di[i + 1];
    final di14 = di[i + 14];
    final r1 = _rol32(di1, 14) ^ _rol32(di1, 25) ^ (di1 >>> 3);
    final r2 = _rol32(di14, 13) ^ _rol32(di14, 15) ^ (di14 >>> 10);
    di.add(_u32(di0 + di[i + 9] + r1 + r2));
    di0 = di1;
  }
  return di;
}

List<int> _mixRounds(
  List<int> state,
  List<int> rounds,
  List<int> di,
  List<int> tt,
  int ivV1,
) {
  var s = List<int>.from(state);
  int idx(int k) => rounds[k];
  for (var i = 0; i < rounds[0]; i++) {
    final base = ivV1 + i;
    final w = di[base & 127];
    final n1 = ((s[idx(3)] ^ s[idx(4)]) & s[idx(1)]) ^ s[idx(3)];
    final n2 =
        _rol32(s[idx(1)], 26) ^ _rol32(s[idx(1)], 21) ^ _rol32(s[idx(1)], 7);
    final n4 = _u32(w + n1 + n2 + tt[base & 63] + s[idx(5)]);
    final n5 =
        _rol32(s[idx(2)], 30) ^ _rol32(s[idx(2)], 19) ^ _rol32(s[idx(2)], 10);
    final n6 =
        (s[idx(2)] & s[idx(6)]) | ((s[idx(2)] | s[idx(6)]) & s[idx(7)]);
    final n7 = _u32(n5 + n6);
    final old = s[idx(9)];
    final last = s[s.length - 1];
    s = <int>[last, ...s.sublist(0, s.length - 1)];
    s[idx(10)] = _u32(n7 + n4);
    s[idx(8)] = _u32(old + n4);
  }
  return s;
}

Uint8List _branch0F13(
  List<int> querySM3,
  List<int> bodyMD5,
  List<int> ts,
  int khronos,
  int ivV0,
) {
  final ivV1 = _branch0IV[min(ivV0, _branch0IV.length - 1)];
  final countV1 = (ivV1 + khronos + 1) & 255;
  final countV2 = ivV1 + khronos;
  final tt = _branch0TT.map((v) => _ror32(v, countV1)).toList();
  final n0 = (countV2 + 2) & 7;
  const seed = [0xfa, 0x45, 0x61, 0xd7];
  final pad = List<int>.generate(
    seed.length,
    (i) {
      final combined = seed[i] | (seed[i] << 8);
      return (combined >> n0) & 255;
    },
  );
  final data = BytesBuilder();
  data.add(querySM3);
  data.add(bodyMD5);
  data.add(ts);
  data.add(pad);
  data.add(_decodeHex('00000000000001a0'));
  final di = _expandWords(data.toBytes());
  final init = _branch0Init.map((v) => _ror32(v, countV2 & 31)).toList();
  final d = _mixRounds(init, _branch0Rounds[ivV0], di, tt, ivV1);
  final ret = BytesBuilder();
  for (var i = 0; i < 8; i++) {
    ret.add(_be32(_u32(d[i] + init[i])));
  }
  final retBytes = ret.toBytes();
  for (var i = 0; i < 16; i++) {
    retBytes[i] = retBytes[i] ^ retBytes[16 + i];
  }
  final out = BytesBuilder();
  out.add(retBytes.sublist(0, 16));
  out.add(_le32(_sumMD5(retBytes.sublist(0, 16))));
  return out.toBytes();
}

int _md5V3Step(int kind, int a, int b, int c, int d, int m, int shift, int constant) {
  int f;
  switch (kind) {
    case 0:
      f = (b & c) | ((~b & _u32Mask) & d);
    case 1:
      f = (b & d) | (c & (~d & _u32Mask));
    case 2:
      f = b ^ c ^ d;
    default:
      f = c ^ (b | (~d & _u32Mask));
  }
  return _u32(b + _rol32(_u32(a + f + m + constant), shift));
}

Uint8List _md5SumV3(List<int> message, int countV2, List<int> orders, int countV1) {
  final sv = _branch2SV.map((v) => _ror32(v, countV1)).toList();
  final start = <int>[
    _ror32(0x79e0f2fb, countV2),
    _ror32(0xc8b52570, countV2),
    _ror32(0xebc2f8cd, countV2),
    _ror32(0x7c104d93, countV2),
  ];
  final endCount = (countV2 + 6) & 255;
  final end = <int>[
    _ror32(0x19be4866, endCount),
    _ror32(0xe85986b4, endCount),
    _ror32(0xe19b326e, endCount),
    _ror32(0x71d1d7d4, endCount),
  ];
  final m = List<int>.generate(16, (i) => _readLe32(message, i * 4));
  var a = start[0], b = start[1], c = start[2], d = start[3];

  void run(int kind, List<int> shifts, int offset) {
    for (var i = 0; i < 16; i++) {
      final phase = i & 3;
      final w = m[orders[offset + i]];
      final k = sv[offset + i];
      int next;
      switch (phase) {
        case 0:
          next = _md5V3Step(kind, a, b, c, d, w, shifts[i], k);
          a = next;
        case 1:
          next = _md5V3Step(kind, d, a, b, c, w, shifts[i], k);
          d = next;
        case 2:
          next = _md5V3Step(kind, c, d, a, b, w, shifts[i], k);
          c = next;
        default:
          next = _md5V3Step(kind, b, c, d, a, w, shifts[i], k);
          b = next;
      }
    }
  }

  run(0, [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22], 0);
  run(1, [5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20], 16);
  run(2, [4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23], 32);
  run(3, [6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21], 48);

  final ret = BytesBuilder();
  ret.add(_le32(_u32((start[0] + a) ^ end[0])));
  ret.add(_le32(_u32((start[1] + b) ^ end[1])));
  ret.add(_le32(_u32((start[2] + c) ^ end[2])));
  ret.add(_le32(_u32((start[3] + d) ^ end[3])));
  ret.add(_le32(_sumMD5(ret.toBytes())));
  return ret.toBytes();
}

Uint8List _branch2F13(
  int iv,
  List<int> querySM3,
  List<int> bodyMD5,
  List<int> ts,
  int khronos,
) {
  final v = (iv & 13) * 86;
  final ivV0 = ((v >> 15) & 255) + ((v >> 8) & 255);
  const n1s = <int>[
    0x8980f29b, 0xeb549c7f, 0xb08726db, 0xd40cb5e6, 0xe8f559e4,
  ];
  final n1 = n1s[min(ivV0, n1s.length - 1)];
  final countV1 = (n1 + khronos + 1) & 255;
  final countV2 = n1 + khronos;
  final shift = (countV2 + 5) & 7;
  const seed = <int>[0x84, 0x96, 0x77, 0x9d, 0xd4, 0x15, 0x0b, 0xf8];
  final pad = List<int>.generate(
    seed.length,
    (i) {
      final combined = seed[i] | (seed[i] << 8);
      return (combined >> shift) & 255;
    },
  );
  final input = BytesBuilder();
  input.add(querySM3);
  input.add(bodyMD5);
  input.add(ts);
  input.add(pad);
  input.add(_decodeHex('a0010000'));
  final all = _branch2Orders;
  final begin = ivV0 << 6;
  return _md5SumV3(
    input.toBytes(),
    countV2,
    all.sublist(begin, begin + 64),
    countV1,
  );
}

// ---------------------------------------------------------------------------
// medusa（sign/medusa.go + sign/aes.go）
// ---------------------------------------------------------------------------

Uint8List xmxor(List<int> data, List<int> key) {
  final n = data.length;
  final encoded = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final at = (i * 4) & 28;
    final d0 = key[at];
    final d1 = key[at + 1];
    var d2 = _u32(((data[i] << 4) & 0xFF) | (data[i] >> 4)) + d0;
    d2 &= 0xFF;
    d2 = _u32(~d2) & 0xFF;
    d2 ^= d1;
    d2 = ((d2 << 3) & 0xFF) | (d2 >> 5);
    d2 = (d2 + d1) & 0xFF;
    d2 ^= d0;
    encoded[n - i - 1] = (~d2) & 0xFF;
  }
  final last = encoded[n - 1] ^ encoded[n - 2];
  final first = encoded[0];
  encoded[0] = ((~last) & 0xFF) + first & 0xFF;
  encoded[1] = ((encoded[0] ^ encoded[n - 1] ^ 254) + encoded[1]) & 0xFF;
  final shifted = ((encoded[1] << 3) & 0xFF) | (encoded[1] >> 5);
  final fix2 = ((last - first) & 0xFF) ^ (shifted ^ 2);
  encoded[2] = (encoded[2] + fix2) & 0xFF;
  for (var i = 0; i < n - 4; i++) {
    final sh = ((encoded[i + 2] << 3) & 0xFF) | (encoded[i + 2] >> 5);
    final temp = sh ^ encoded[i + 1] ^ ((i + 3) & 0xFF);
    encoded[i + 3] = ((~temp) & 0xFF) + encoded[i + 3] & 0xFF;
  }
  encoded[n - 1] ^= encoded[n - 2];
  var sum = 0;
  for (var i = 1; i < n; i++) {
    sum = _u32(sum + encoded[i]);
  }
  encoded[0] = ((encoded[0] ^ encoded[1]) + (sum & 0xFF)) & 0xFF;
  return encoded;
}

(Uint8List, Uint8List) keyHash(List<int> signKey, int random) {
  final buf = BytesBuilder();
  buf.add(signKey);
  buf.add(_le32(random));
  buf.add(signKey);
  final hash = sm3Sum(buf.toBytes());
  final d1 = (random >> 16) & 255;
  var d2 = _u32((d1 << 11) | (random >>> 24));
  d2 ^= d1 >>> 5;
  d2 ^= d1;
  d2 = _u32(~d2);
  return (hash, Uint8List.fromList(_le32(d2)));
}

Uint8List _deviceProto(String deviceID) {
  final out = BytesBuilder();
  out.add(_protoSInt(1, 1));
  out.add(_protoSInt(2, 2));
  out.add(_protoString(3, signAppID));
  out.add(_protoString(4, deviceID));
  out.add(_protoString(5, 'Ai6svO3PyrwDOUSmO6ZcResxu'));
  out.add(_protoString(6, '!noperm!'));
  out.add(_protoSInt(7, -888888));
  out.add(_protoSInt(8, -888888));
  out.add(_protoSInt(9, 3));
  out.add(_protoSInt(10, -888888));
  out.add(_protoString(11, '!notset!'));
  out.add(_protoString(12, 'Asia/Shanghai,8'));
  out.add(_protoString(13, 'zh_CN'));
  out.add(_protoSInt(14, 4));
  out.add(_protoFloat(16, 255.24993896484375));
  out.add(_protoFloat(17, 35.58599090576172));
  out.add(_protoFloat(18, 3.467449188232422));
  out.add(_protoFloat(19, 3.467449188232422));
  out.add(_protoFloat(20, 255.1754913330078));
  out.add(_protoFloat(21, 42.17544174194336));
  out.add(_protoString(22, '16'));
  out.add(_protoSInt(23, 41));
  out.add(_protoSInt(24, 36));
  out.add(_protoSInt(25, 1728388016635));
  out.add(_protoSInt(26, 1728388016635));
  out.add(_protoSInt(27, 1728388016635));
  out.add(_protoSInt(28, 1728388016637));
  out.add(_protoSInt(29, -1));
  out.add(_protoString(30, '25053RT47C'));
  out.add(_protoString(31, 'Redmi'));
  out.add(_protoString(32, '25053RT47C'));
  out.add(_protoString(33, '25053RT47C'));
  out.add(_protoString(34, 'Xiaomi'));
  out.add(_protoString(35, 'Redmi'));
  out.add(_protoString(36, 'Redmi'));
  out.add(_protoSInt(38, 31));
  return out.toBytes();
}

String assembleMedusa(
  String rawURL,
  List<int>? body,
  bool hasBody,
  int khronos,
  String deviceID,
  String versionName,
  HongguoEntropy entropy,
) {
  final bodyMD5 = hasBody ? _md5Raw(body!) : Uint8List(16);
  var queryRaw = '';
  final idx = rawURL.indexOf('?');
  if (idx >= 0) queryRaw = rawURL.substring(idx + 1);
  final querySM3 = sm3Sum(utf8.encode(queryRaw));
  final ts = _le32(khronos);
  final queryBodyTS = _hashF13(querySM3, bodyMD5, ts, khronos);
  final check =
      _u32((querySM3[0] & 63) << 14) | 0x18000001 | ((queryBodyTS[0] & 63) << 8);

  var nested = BytesBuilder();
  nested.add(_protoSInt(1, 111));
  nested.add(_protoSInt(2, 10));
  nested.add(_protoSInt(3, 694367));
  nested.add(_protoSInt(5, 586952199));
  final nestedBytes = nested.toBytes();

  var nested13 = BytesBuilder();
  nested13.add(_protoSInt(1, entropy.nowSecs));
  nested13.add(_protoSInt(2, -2));
  nested13.add(_protoSInt(4, 200));
  final nested13Bytes = nested13.toBytes();

  var env = BytesBuilder();
  env.add(_protoSInt(1, entropy.envLaunch));
  env.add(_protoSInt(2, 146331399));
  env.add(_protoSInt(3, 146331396));
  env.add(_protoSInt(5, 7));
  env.add(_protoString(6, 'v04.06.04.03-bugfix'));
  env.add(_protoSInt(7, entropy.envPID));
  env.add(_protoBytes(12, _deviceProto(deviceID)));
  env.add(_protoBytes(13, nested13Bytes));
  env.add(_protoString(14, versionName));
  final envBytes = env.toBytes();

  var qh = BytesBuilder();
  qh.add(utf8.encode(queryRaw));
  qh.add(bodyMD5);
  qh.add(utf8.encode('none'));
  final queryHash = sm3Sum(qh.toBytes());

  final fixed1 = _decodeHex('f7e85ffad7d7dc3bd62ac87057cf6118');
  final fixed2 = _decodeHex('4001000000000000');
  var message = BytesBuilder();
  message.add(_protoBytes(1, fixed1));
  message.add(_protoSInt(2, 3));
  message.add(_protoSInt(3, entropy.messageRandom));
  message.add(_protoString(4, signAppID));
  message.add(_protoString(5, deviceID));
  message.add(_protoString(6, signChannelID));
  message.add(_protoString(7, versionName));
  message.add(_protoString(8, 'v04.06.04-ml-android'));
  message.add(_protoSInt(9, 67503104));
  message.add(_protoBytes(10, fixed2));
  message.add(_protoSInt(12, khronos));
  message.add(_protoBytes(13, queryBodyTS));
  message.add(_protoBytes(14, querySM3.sublist(0, 6)));
  message.add(_protoBytes(15, nestedBytes));
  message.add(_protoString(16, 'AXYQOS6n2m60x1fVZHIrH3iol'));
  message.add(_protoSInt(17, khronos));
  message.add(_protoBytes(19, queryHash));
  message.add(_protoString(20, 'none'));
  message.add(_protoSInt(21, 312));
  message.add(_protoBytes(23, envBytes));
  message.add(_protoString(
    24,
    '{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,'
    '"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}',
  ));

  final (hash, seed) = keyHash(_medusaSignKey, entropy.random);
  var transformed = xmxor(message.toBytes(), hash);
  final prefixBytes = BytesBuilder();
  prefixBytes.add(fixed2);
  prefixBytes.add(transformed);
  transformed = prefixBytes.toBytes();
  // 原位反转。
  for (var i = 0, j = transformed.length - 1; i < j; i++, j--) {
    final t = transformed[i];
    transformed[i] = transformed[j];
    transformed[j] = t;
  }
  for (var i = 0; i < transformed.length; i++) {
    transformed[i] = transformed[i] ^ seed[(~i) & 3];
  }
  var packed = BytesBuilder();
  packed.addByte(0x35);
  packed.add(_le32(entropy.packedRandom));
  packed.add(_le32(check));
  packed.add(transformed);
  packed.addByte((entropy.random >> 16) & 255);
  packed.addByte((entropy.random >> 24) & 255);

  final encrypted = _AesV3(_medusaAESKey, khronos)
      .encrypt(packed.toBytes(), _medusaAESIV);
  final version = _decodeHex('03000000f7e85ffad7d7dc3bd62ac87057cf6118');
  final prefix = Uint8List(20);
  for (var i = 0; i < 5; i++) {
    final v = _readLe32(version, i * 4);
    prefix.setRange(i * 4, i * 4 + 4, _le32(v ^ khronos));
  }
  final out = BytesBuilder();
  out.add(prefix);
  out.addByte(entropy.random & 255);
  out.addByte((entropy.random >> 8) & 255);
  out.addByte(0);
  out.addByte(1);
  out.add(encrypted);
  return base64Encode(out.toBytes());
}

// ---------------------------------------------------------------------------
// aesV3（sign/aes.go）
// ---------------------------------------------------------------------------

final List<List<int>> _aesCon2 = <List<int>>[
  [1, 0, 2, 3],
  [2, 0, 3, 1],
  [0, 1, 3, 2],
  [1, 0, 2, 3],
];

final List<List<int>> _aesOrder = <List<int>>[
  [0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3],
  [0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11],
  [0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15],
  [0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3],
];

final List<int> _aesInitWord = <int>[
  0xca025ddc, 0x823dc546, 0xc9420583, 0xc298225f,
];

class _AesV3 {
  _AesV3(List<int> key, int khronos)
      : box = Uint8List.fromList(
          _sboxBytes.sublist((khronos & 3) * 256, (khronos & 3) * 256 + 256),
        ),
        word = khronos & 3 {
    con2 = _aesCon2[word];
    order = _aesOrder[word];
    keys = _expandAES(key, word);
  }

  final Uint8List box;
  final int word;
  late final List<int> con2;
  late final List<int> order;
  late final List<Uint8List> keys;

  static List<Uint8List> _expandAES(List<int> key, int word) {
    final init = _aesInitWord[word];
    final box =
        _sboxBytes.sublist(word * 256, word * 256 + 256);
    final le = Uint8List(4)
      ..setRange(0, 4, _le32(init));
    final initial = Uint8List(16);
    for (var i = 0; i < 4; i++) {
      initial.setRange(i * 4, i * 4 + 4, le);
    }
    final expanded = BytesBuilder();
    final exp = Uint8List.fromList(initial);
    for (var i = 0; i < exp.length; i++) {
      exp[i] ^= key[i % key.length];
    }
    expanded.add(exp);
    expanded.add(Uint8List(32));
    final buf = expanded.toBytes();
    var rounds = 8;
    for (var i = 4; i < 12; i++) {
      final at = 4 * (i - 1);
      var a = buf[at], b = buf[at + 1], c = buf[at + 2], d = buf[at + 3];
      if (i & 3 == 0) {
        final t = ((init >>> (rounds & 24)) ^ box[b]) & 255;
        b = box[c];
        c = box[d];
        d = box[a];
        a = t;
      }
      rounds += 2;
      buf[at + 4] = a ^ buf[at - 12];
      buf[at + 5] = b ^ buf[at - 11];
      buf[at + 6] = c ^ buf[at - 10];
      buf[at + 7] = d ^ buf[at - 9];
    }
    final keys = List<Uint8List>.generate(
      12,
      (i) => Uint8List.fromList(buf.sublist(i * 4, i * 4 + 4)),
    );
    return keys;
  }

  void _addCon(List<List<int>> state, List<Uint8List> keysSlice) {
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        state[i][j] ^= keysSlice[i][con2[j]];
      }
    }
  }

  void _sub(List<List<int>> state) {
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        state[i][j] = box[state[i][j]];
      }
    }
    final old = List<List<int>>.generate(
      4,
      (i) => List<int>.from(state[i]),
    );
    for (var i = 0; i < 4; i++) {
      state[i] = old[con2[i]];
    }
  }

  void _shift(List<List<int>> state) {
    final flat = List<int>.filled(16, 0);
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        flat[i * 4 + j] = state[i][j];
      }
    }
    for (var i = 0; i < 16; i++) {
      state[i ~/ 4][i % 4] = flat[order[i]];
    }
  }

  static void _shiftCon(List<List<int>> state, List<int> con) {
    final old = List<List<int>>.generate(
      4,
      (i) => List<int>.from(state[i]),
    );
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        state[i][j] = old[i][con[j]];
      }
    }
  }

  static void _mixColumns(List<List<int>> state) {
    int xt(int x) {
      final v = (x << 1) & 0xFF;
      return (x & 128) != 0 ? v ^ 0x1b : v;
    }

    for (var i = 0; i < 4; i++) {
      final t = state[0][i] ^ state[1][i] ^ state[2][i] ^ state[3][i];
      final u = state[0][i];
      state[0][i] ^= t ^ xt(state[0][i] ^ state[1][i]);
      state[1][i] ^= t ^ xt(state[1][i] ^ state[2][i]);
      state[2][i] ^= t ^ xt(state[2][i] ^ state[3][i]);
      state[3][i] ^= t ^ xt(state[3][i] ^ u);
    }
  }

  Uint8List _block(List<int> value) {
    final state = List<List<int>>.generate(
      4,
      (i) => List<int>.from(value.sublist(i * 4, i * 4 + 4)),
    );
    _addCon(state, keys.sublist(0, 4));
    for (var i = 1; i < 3; i++) {
      _sub(state);
      _shift(state);
      if (i == 1) {
        _shiftCon(state, con2);
        _mixColumns(state);
      }
      _addCon(state, keys.sublist(i * 4, i * 4 + 4));
    }
    for (var i = 0; i < 4; i++) {
      for (var j = 0; j < 4; j++) {
        state[i][j] ^= keys[4 + i][j];
      }
    }
    final out = BytesBuilder();
    for (var i = 0; i < 4; i++) {
      out.add(state[i]);
    }
    return out.toBytes();
  }

  Uint8List encrypt(List<int> data, List<int> iv) {
    final source = Uint8List.fromList(data);
    final plaintext = Uint8List(32);
    for (var i = 0; i < 31; i++) {
      final at = i * 8;
      final n0 = (source[at] >> 4) & 2;
      final n1 = n0 | (source[at + 1] & 64);
      final n2 = n1 | ((source[at + 2] >> 2) & 1);
      final n3 = n2 | ((source[at + 3] << 3) & 128);
      final n4 = n3 | ((source[at + 4] >> 1) & 4);
      final n5 = n4 | ((source[at + 5] << 3) & 16);
      final n6 = n5 | ((source[at + 6] << 5) & 32);
      plaintext[i] = n6 | ((source[at + 7] >> 4) & 8);
    }
    plaintext[31] = 1;
    final blocks = BytesBuilder();
    var previous = Uint8List.fromList(iv);
    for (var off = 0; off < 32; off += 16) {
      final mixed = Uint8List(16);
      for (var i = 0; i < 16; i++) {
        mixed[i] = plaintext[off + i] ^ previous[i];
      }
      final value = _block(mixed);
      blocks.add(value);
      previous = Uint8List.fromList(value);
    }
    final blockBytes = blocks.toBytes();
    final out = Uint8List.fromList(source);
    for (var i = 0; i < 31; i++) {
      final at = i * 8;
      final k = blockBytes[i];
      out[at] &= 0xdf;
      out[at] |= (k << 4) & 32;
      out[at + 1] &= 0xbf;
      out[at + 1] |= k & 64;
      out[at + 2] &= 0xfb;
      out[at + 2] |= (k << 2) & 4;
      out[at + 3] &= 0xef;
      out[at + 3] |= (k >> 3) & 16;
      out[at + 4] &= 0xf7;
      out[at + 4] |= (k + k) & 8;
      out[at + 5] &= 0xfd;
      out[at + 5] |= (k >> 3) & 2;
      out[at + 6] &= 0xfe;
      out[at + 6] |= (k >> 5) & 1;
      out[at + 7] &= 0x7f;
      out[at + 7] |= (k << 4) & 128;
    }
    final result = BytesBuilder();
    result.addByte(blockBytes[31]);
    result.add(out);
    return result.toBytes();
  }
}

// ---------------------------------------------------------------------------
// 熵与请求签名（sign/request.go）
// ---------------------------------------------------------------------------

class HongguoEntropy {
  HongguoEntropy({
    this.envLaunch = 0,
    this.envPID = 0,
    this.nowSecs = 0,
    this.messageRandom = 0,
    this.random = 0,
    this.packedRandom = 0,
    this.gorgonRandom = 0,
    this.heliosRandom = 0,
  });

  final int envLaunch;
  final int envPID;
  final int nowSecs;
  final int messageRandom;
  final int random;
  final int packedRandom;
  final int gorgonRandom;
  final int heliosRandom;
}

HongguoEntropy drawEntropy(int nowMillis) {
  final buf = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    buf[i] = Random.secure().nextInt(256);
  }
  final n = _readLe64(buf, 0);
  final u16 = buf[8] | (buf[9] << 8);
  return HongguoEntropy(
    envLaunch: 100 + (n % 21),
    envPID: 10001 + (u16 % 2000),
    nowSecs: nowMillis ~/ 1000,
    messageRandom: _readLe32(buf, 0),
    random: _readLe32(buf, 4),
    packedRandom: _readLe32(buf, 8),
    gorgonRandom: buf[12] | (buf[13] << 8),
    heliosRandom: _readLe32(buf, 12),
  );
}

/// 组装一条 GET/POST 的查询串与签名头。
/// [pairs] 必须按线上客户端的顺序排列；ts 与 _rticket 由本函数追加。
(HongguoSignedQuery, Map<String, String>) hongguoSignRequest(
  String path,
  List<(String, String)> pairs,
  int nowMillis,
  String deviceID,
  String versionName, [
  List<int>? body,
  HongguoEntropy? entropy,
]) {
  final ent = entropy ?? drawEntropy(nowMillis);
  final hasBody = body != null;
  final bodyMD5 = hasBody ? _md5Raw(body) : Uint8List(16);
  final base = nowMillis;
  var query = '';
  var ticket = 0;
  var khronos = 0;
  for (var offset = 0; offset < 32; offset++) {
    ticket = base + offset;
    khronos = ticket ~/ 1000;
    final withTicket = <(String, String)>[
      ...pairs,
      ('ts', khronos.toString()),
      ('_rticket', ticket.toString()),
    ];
    query = _encodeQuery(withTicket);
    final sum = sm3Sum(utf8.encode(query));
    if (_branchOf(sum, bodyMD5, _le32(khronos)) != 1) {
      break;
    }
  }
  final nowSecs = ent.nowSecs != 0 ? ent.nowSecs : khronos;
  // x-medusa 对该 URL 取哈希；服务端对 fqnovel 域的请求同样接受该值。
  final rawURL = 'https://reading.snssdk.com$path?$query';
  final headers = <String, String>{
    'Accept': 'application/json; charset=utf-8,application/x-protobuf',
    'x-xs-from-web': '0',
    'x-ss-req-ticket': ticket.toString(),
    'x-tt-request-tag': 't=0;n=0',
    'sdk-version': '2',
    'passport-sdk-version': '50561',
    'x-vc-bdturing-sdk-version': '3.7.2.cn',
    'x-khronos': khronos.toString(),
    'x-ladon': base64Encode(_be32(khronos)),
    'x-argus': base64Encode(_le32(khronos)),
    'x-gorgon': xGorgon(query, body, hasBody, khronos, ent.gorgonRandom),
    'x-helios': assembleHelios(khronos, ent.heliosRandom),
    'x-medusa': assembleMedusa(
      rawURL, body, hasBody, khronos, deviceID, versionName,
      HongguoEntropy(
        envLaunch: ent.envLaunch,
        envPID: ent.envPID,
        nowSecs: nowSecs,
        messageRandom: ent.messageRandom,
        random: ent.random,
        packedRandom: ent.packedRandom,
        gorgonRandom: ent.gorgonRandom,
        heliosRandom: ent.heliosRandom,
      ),
    ),
    'x-tt-dt': '',
  };
  if (hasBody) {
    headers['Content-Type'] = 'application/json; charset=UTF-8';
    headers['x-ss-stub'] = hexEncode(_md5Raw(body)).toUpperCase();
  }
  return (
    HongguoSignedQuery(query: query, ticket: ticket, khronos: khronos),
    headers,
  );
}

class HongguoSignedQuery {
  const HongguoSignedQuery({
    required this.query,
    required this.ticket,
    required this.khronos,
  });

  final String query;
  final int ticket;
  final int khronos;
}

String _encodeQuery(List<(String, String)> pairs) {
  return pairs.map((p) => '${_encodeComponent(p.$1)}=${_encodeComponent(p.$2)}').join('&');
}

const String _unreserved = "-_.!~*'()";

String _encodeComponent(String s) {
  final bytes = utf8.encode(s);
  final sb = StringBuffer();
  for (final c in bytes) {
    final isUpper = c >= 0x41 && c <= 0x5A;
    final isLower = c >= 0x61 && c <= 0x7A;
    final isDigit = c >= 0x30 && c <= 0x39;
    final isUnreserved = _unreserved.codeUnits.contains(c);
    if (isUpper || isLower || isDigit || isUnreserved) {
      sb.writeCharCode(c);
    } else {
      sb.write('%${c.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return sb.toString();
}
