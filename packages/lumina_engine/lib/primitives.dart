import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

(Uint8List, Uint8List)? splitEnvelope(String text) {
  final split = text.indexOf('.');
  if (split < 340 || text.trimLeft().startsWith('{')) return null;
  try {
    return (
      uncb64(text.substring(0, split)),
      uncb64(text.substring(split + 1)),
    );
  } on FormatException {
    return null;
  }
}

const _alphabet =
    '5iW7S0GX6uf1cv3ny4q8es2Q+bdkYgKOIT/tzhAxUrFlVPmow9BHCZNMDpEaJRLj';
const _standard =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
String cb64(List<int> bytes) => base64Encode(bytes).split('').map((c) {
  final i = _standard.indexOf(c);
  return i < 0 ? c : _alphabet[i];
}).join();
Uint8List uncb64(String text) => base64Decode(
  base64.normalize(
    text.trim().split('').map((c) {
      final i = _alphabet.indexOf(c);
      return i < 0 ? c : _standard[i];
    }).join(),
  ),
);
Uint8List hexBytes(String text) => Uint8List.fromList([
  for (var i = 0; i < text.length; i += 2)
    int.parse(text.substring(i, i + 2), radix: 16),
]);
Uint8List pad(List<int> data) {
  final n = 16 - data.length % 16;
  return Uint8List.fromList([...data, ...List.filled(n, n)]);
}

Uint8List unpad(List<int> data) {
  if (data.isEmpty || data.length % 16 != 0)
    throw const FormatException('Invalid block length');
  final n = data.last;
  if (n < 1 || n > 16 || data.skip(data.length - n).any((v) => v != n))
    throw const FormatException('Invalid padding');
  return Uint8List.fromList(data.take(data.length - n).toList());
}

List<int> xor(List<int> a, List<int> b) =>
    List.generate(a.length, (i) => a[i] ^ b[i]);

/// 标准 AES 核同时用于解析器 CBC 和引擎布局适配，协议变体仅在 f() 中。
class Aes128 {
  Aes128(List<int> key) {
    if (key.length != 16) throw const FormatException('AES key length');
    final w = List<int>.from(key);
    var rc = 1;
    for (var i = 4; i < 44; i++) {
      var t = w.sublist((i - 1) * 4, i * 4);
      if (i % 4 == 0) {
        t = [sbox[t[1]] ^ rc, sbox[t[2]], sbox[t[3]], sbox[t[0]]];
        rc = mul(rc, 2);
      }
      for (var j = 0; j < 4; j++) {
        w.add(w[(i - 4) * 4 + j] ^ t[j]);
      }
    }
    rounds = [for (var i = 0; i < 11; i++) w.sublist(i * 16, i * 16 + 16)];
  }
  late final List<List<int>> rounds;
  static final sbox = hexBytes(
    '637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16',
  );
  static final inverse = List.generate(256, (i) => sbox.indexOf(i));
  static int mul(int a, int b) {
    var r = 0;
    for (var i = 0; i < 8; i++) {
      if (b & 1 != 0) r ^= a;
      a = ((a << 1) ^ (a & 128 != 0 ? 0x11b : 0)) & 255;
      b >>= 1;
    }
    return r;
  }

  static List<int> transpose(List<int> a) =>
      List.generate(16, (i) => a[(i % 4) * 4 + i ~/ 4]);
  static List<int> shift(List<int> a, {bool inverse = false}) => List.generate(
    16,
    (i) => a[4 * ((i ~/ 4 + (inverse ? -i % 4 : i % 4)) % 4) + i % 4],
  );
  static List<int> mix(List<int> a, {bool inverse = false}) {
    final matrix = inverse ? [14, 11, 13, 9] : [2, 3, 1, 1];
    return List.generate(16, (i) {
      var v = 0;
      for (var j = 0; j < 4; j++) {
        v ^= mul(a[i ~/ 4 * 4 + j], matrix[(j - i % 4) % 4]);
      }
      return v;
    });
  }

  List<int> f(List<int> x) {
    var s = xor(transpose(x), rounds[0]);
    for (var r = 1; r < 10; r++) {
      s = xor(mix(shift(s.map((v) => sbox[v]).toList())), rounds[r]);
    }
    return transpose(shift(s.map((v) => sbox[v]).toList()));
  }

  List<int> decrypt(List<int> input) {
    var s = xor(input, rounds[10]);
    for (var r = 9; r > 0; r--) {
      s = mix(
        xor(shift(s, inverse: true).map((v) => inverse[v]).toList(), rounds[r]),
        inverse: true,
      );
    }
    return xor(
      shift(s, inverse: true).map((v) => inverse[v]).toList(),
      rounds[0],
    );
  }

  Uint8List cbcDecrypt(List<int> data, List<int> iv) {
    if (data.isEmpty || data.length % 16 != 0 || iv.length != 16)
      throw const FormatException('AES CBC length');
    final out = <int>[];
    var previous = iv;
    for (var i = 0; i < data.length; i += 16) {
      final block = data.sublist(i, i + 16);
      out.addAll(xor(decrypt(block), previous));
      previous = block;
    }
    return unpad(out);
  }
}

BigInt _big(List<int> bytes) {
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b);
  }
  return n;
}

Uint8List _bytes(BigInt n, int length) {
  final out = Uint8List(length);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (n & BigInt.from(255)).toInt();
    n >>= 8;
  }
  if (n != BigInt.zero) throw const FormatException('RSA overflow');
  return out;
}

class _Der {
  _Der(this.data);
  final List<int> data;
  var offset = 0;
  (int, List<int>) read() {
    if (offset + 2 > data.length) throw const FormatException('DER truncated');
    final tag = data[offset++];
    var n = data[offset++];
    if (n & 128 != 0) {
      final count = n & 127;
      if (count == 0 || count > 4 || offset + count > data.length)
        throw const FormatException('DER length');
      n = 0;
      for (var i = 0; i < count; i++) {
        n = n * 256 + data[offset++];
      }
    }
    if (offset + n > data.length) throw const FormatException('DER bounds');
    final bytes = data.sublist(offset, offset + n);
    offset += n;
    return (tag, bytes);
  }
}

class RsaKey {
  RsaKey(this.n, this.e, [this.d, this.p, this.q]);
  final BigInt n, e;
  final BigInt? d;
  final BigInt? p, q;
  factory RsaKey.publicDer(List<int> bytes) {
    final root = _Der(_Der(bytes).read().$2);
    final first = root.read();
    final ints = first.$1 == 2
        ? [first, root.read()]
        : () {
            final bit = root.read();
            if (bit.$1 != 3 || bit.$2.first != 0)
              throw const FormatException('RSA SPKI');
            final body = _Der(_Der(bit.$2.sublist(1)).read().$2);
            return [body.read(), body.read()];
          }();
    return RsaKey(_big(ints[0].$2), _big(ints[1].$2));
  }
  factory RsaKey.privateDer(List<int> bytes) {
    final root = _Der(_Der(bytes).read().$2);
    root.read();
    final n = root.read();
    final e = root.read();
    final d = root.read();
    if ([n, e, d].any((v) => v.$1 != 2))
      throw const FormatException('RSA private DER');
    final p = root.read(), q = root.read();
    if (p.$1 != 2 || q.$1 != 2) throw const FormatException('RSA factors');
    final primeP = _big(p.$2), primeQ = _big(q.$2);
    if (primeP * primeQ != _big(n.$2))
      throw const FormatException('RSA factors');
    return RsaKey(_big(n.$2), _big(e.$2), _big(d.$2), primeP, primeQ);
  }
  int get length => (n.bitLength + 7) ~/ 8;
  Uint8List encrypt(List<int> plain, {Random? random}) {
    if (plain.length > length - 11)
      throw const FormatException('RSA input length');
    final rng = random ?? Random.secure();
    final padding = List.generate(
      length - plain.length - 3,
      (_) => rng.nextInt(255) + 1,
    );
    return _bytes(_big([0, 2, ...padding, 0, ...plain]).modPow(e, n), length);
  }

  Uint8List decrypt(List<int> cipher) {
    if (d == null || cipher.length != length || _big(cipher) >= n)
      throw const FormatException('RSA cipher length');
    final c = _big(cipher);
    // 与 SDK 相同的 CRT 路径，减少移动端 RSA 解包的计算量。
    final BigInt message;
    if (p != null && q != null) {
      final m1 = c.modPow(d! % (p! - BigInt.one), p!);
      final m2 = c.modPow(d! % (q! - BigInt.one), q!);
      message = m2 + q! * ((q!.modInverse(p!) * (m1 - m2)) % p!);
    } else {
      message = c.modPow(d!, n);
    }
    final raw = _bytes(message, length);
    final end = raw.indexOf(0, 2);
    if (raw[0] != 0 || raw[1] != 2 || end < 10)
      throw const FormatException('RSA padding');
    return Uint8List.fromList(raw.sublist(end + 1));
  }
}
