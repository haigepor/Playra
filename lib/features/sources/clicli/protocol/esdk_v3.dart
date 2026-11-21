// CliCli 1.0.10 `libmagic_cipher.so` esdk-v3 reference implementation.
//
// Ported 1:1 from the verified Python reference (dm_magic.py). Every routine
// here is checked against 34 golden vectors captured from the device oracle;
// see tool/clicli/check_protocol.dart.
//
// Wire format:
//   03 | chunked(1B) | slot(BE u64) | clen(1B) | code(clen) |
//   zone_len(BE u16) | zone | ct | finalMAC(32B)
//
// `code` is the masked selector list: [nodeCount, sel...]. Selectors index the
// six-algorithm cascade; zone carries one random key per selector.
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

import 'esdk_tables.dart';

/// (algo id, required key length) per selector byte.
const Map<int, List<int>> kAlgoTable = <int, List<int>>{
  0x19: <int>[2, 16], // RC4 variant
  0x3b: <int>[5, 44], // ChaCha variant
  0x75: <int>[6, 16], // Blowfish variant
  0x82: <int>[3, 0], // custom base64
  0x9a: <int>[4, 16], // XTEA variant
  0xe4: <int>[1, 8], // rolling XOR
};

const List<int> kSelectorAlphabet = <int>[0x19, 0x3b, 0x75, 0x82, 0x9a, 0xe4];
const List<int> _kSaltCode = <int>[
  0x77, 0x69, 0x72, 0x65, 0x2d, 0x63, 0x6f, 0x64, 0x65, 0x2d, 0x6d, 0x61,
  0x73, 0x6b,
]; // "wire-code-mask"
const List<int> _kSaltIntegrity = <int>[
  0x70, 0x61, 0x79, 0x6c, 0x6f, 0x61, 0x64, 0x2d, 0x69, 0x6e, 0x74, 0x65,
  0x67, 0x72, 0x69, 0x74, 0x79,
]; // "payload-integrity"

const int kChunkSize = 65536;
const List<int> _kChunkMagic = <int>[0x45, 0x43, 0x53, 0x4d]; // ECSM

const int _m32 = 0xFFFFFFFF;

/// One key slot of the cascade envelope.
class EsdkZoneEntry {
  const EsdkZoneEntry(this.selector, this.key);

  final int selector;
  final Uint8List key;
}

class EsdkV3 {
  EsdkV3._();

  // ------------------------------------------------------------------ hashes

  static Uint8List _sha256(List<int> data) =>
      Uint8List.fromList(c.sha256.convert(data).bytes);

  static Uint8List _hmac(List<int> key, List<int> data) =>
      Uint8List.fromList(c.Hmac(c.sha256, key).convert(data).bytes);

  /// Aliased HMAC used to seed [deriveCode]. The key is zero-padded to 64B,
  /// exactly like the native implementation (pad bytes are 0x36 before XOR).
  static Uint8List _twist(List<int> key, List<int> msg) {
    final k = Uint8List(64)..fillRange(0, 64, 0x36);
    final n = key.length < 64 ? key.length : 64;
    k.setRange(0, n, key);
    final ipad = Uint8List.fromList(<int>[for (final b in k) b ^ 0x36]);
    final opad = Uint8List.fromList(<int>[for (final b in k) b ^ 0x5c]);
    return _sha256(<int>[...opad, ..._sha256(<int>[...ipad, ...msg])]);
  }

  // ------------------------------------------------------------- slot / code

  static int slotOf(int timeSeconds) => (timeSeconds ~/ 3600) & 0xFFFFFFFFFFFF;

  /// Returns `[nodeCount, selector...]` — the *unmasked* code.
  static Uint8List deriveCode(
    List<int> key,
    int timeSeconds, [
    int nodeCount = 0,
  ]) {
    final mac = _twist(key, _u64be(slotOf(timeSeconds)));
    final nc = nodeCount < 1 ? (mac[1] % 3 + 2) : nodeCount.clamp(2, 8);
    final out = <int>[nc];
    var st = mac;
    for (var k = 0; k < nc; k++) {
      out.add(kSelectorAlphabet[st[0] % 6]);
      final d = _sha256(<int>[
        for (final b in st) b ^ 0x36,
        ...List<int>.filled(32, 0x36),
        k,
      ]);
      st = _sha256(<int>[
        for (final b in d) b ^ 0x5c,
        ...List<int>.filled(32, 0x5c),
        ...d,
      ]);
    }
    return Uint8List.fromList(out);
  }

  static Uint8List _codeMac(List<int> key, int timeSeconds) => _hmac(
    key,
    <int>[..._u64be(slotOf(timeSeconds)), ..._kSaltCode],
  );

  static Uint8List maskCode(
    List<int> key,
    int timeSeconds,
    List<int> rawCode,
  ) {
    final cm = _codeMac(key, timeSeconds);
    final out = Uint8List(rawCode.length)..[0] = rawCode[0];
    for (var i = 1; i < rawCode.length; i++) {
      out[i] = rawCode[i] ^ cm[(i - 1) & 0x1f];
    }
    return out;
  }

  static Uint8List _unmaskCode(
    List<int> key,
    int slot,
    List<int> wireCode,
    List<int> salt,
  ) {
    final cm = _hmac(key, <int>[..._u64be(slot), ...salt]);
    final out = Uint8List(wireCode.length)..[0] = wireCode[0];
    for (var i = 1; i < wireCode.length; i++) {
      out[i] = wireCode[i] ^ cm[(i - 1) & 0x1f];
    }
    return out;
  }

  // ------------------------------------------------------------- algorithms

  static int _rotl32(int x, int n) =>
      ((x << n) | ((x & _m32) >> (32 - n))) & _m32;
  static int _rotl8(int x, int n) => ((x << n) | (x >> (8 - n))) & 0xff;
  static int _rotr8(int x, int n) => ((x >> n) | (x << (8 - n))) & 0xff;

  /// algo 1 — rolling XOR + ROL8 (8-byte key).
  static Uint8List _algo1(List<int> key, List<int> data, {required bool dec}) {
    final out = Uint8List(data.length);
    var st = 0x5a;
    for (var i = 0; i < data.length; i++) {
      if (dec) {
        final p = key[i & 7] ^ ((st + i) & 0xff) ^ _rotr8(data[i], 3);
        out[i] = p;
        st = data[i];
      } else {
        st = _rotl8(data[i] ^ ((i + st) & 0xff) ^ key[i & 7], 3);
        out[i] = st;
      }
    }
    return out;
  }

  /// algo 2 — RC4 table variant (16-byte key, symmetric).
  static Uint8List _algo2(List<int> key, List<int> data) {
    final s = List<int>.from(kRc4S0);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (s[i] + (i ^ 0xAA) + j + key[i & 0xf]) & 0xff;
      final t = s[i];
      s[i] = s[j];
      s[j] = t;
    }
    final out = Uint8List(data.length);
    var j1 = 0x11;
    var j2 = 0x22;
    for (var m = 0; m < data.length; m++) {
      j1 = (j1 + j2 + 1) & 0xff;
      final t1 = s[j1];
      final j2n = (t1 + j2) & 0xff;
      s[j1] = s[j2n];
      s[j2n] = t1;
      final kb = key[m & 0xf];
      final idx = ((s[j1] + t1) ^ kb) & 0xff;
      out[m] = s[idx] ^ data[m];
      j2 = j2n;
    }
    return out;
  }

  /// algo 3 — custom base64 (keyless).
  static Uint8List _algo3(List<int> data, {required bool dec}) {
    final alpha = kB64Alpha.codeUnits;
    if (!dec) {
      final out = BytesBuilder(copy: false);
      final n = data.length;
      final full = n ~/ 3 * 3;
      for (var i = 0; i < full; i += 3) {
        final b0 = data[i], b1 = data[i + 1], b2 = data[i + 2];
        out.addByte(alpha[b0 >> 2]);
        out.addByte(alpha[((b0 & 3) << 4) | (b1 >> 4)]);
        out.addByte(alpha[((b1 & 0xf) << 2) | (b2 >> 6)]);
        out.addByte(alpha[b2 & 0x3f]);
      }
      final rem = n - full;
      if (rem == 2) {
        final b0 = data[n - 2], b1 = data[n - 1];
        out.addByte(alpha[b0 >> 2]);
        out.addByte(alpha[((b0 & 3) << 4) | (b1 >> 4)]);
        out.addByte(alpha[(b1 & 0xf) << 2]);
      } else if (rem == 1) {
        final b0 = data[n - 1];
        out.addByte(alpha[b0 >> 2]);
        out.addByte(alpha[(b0 & 3) << 4]);
      }
      return out.toBytes();
    }

    final idx = <int, int>{for (var i = 0; i < alpha.length; i++) alpha[i]: i};
    final out = BytesBuilder(copy: false);
    final n = data.length;
    var i = 0;
    while (i + 4 <= n) {
      final c0 = idx[data[i]]!, c1 = idx[data[i + 1]]!;
      final c2 = idx[data[i + 2]]!, c3 = idx[data[i + 3]]!;
      out.addByte((c0 << 2) | (c1 >> 4));
      out.addByte(((c1 & 0xf) << 4) | (c2 >> 2));
      out.addByte(((c2 & 3) << 6) | c3);
      i += 4;
    }
    final rem = n - i;
    if (rem == 3) {
      final c0 = idx[data[i]]!, c1 = idx[data[i + 1]]!, c2 = idx[data[i + 2]]!;
      out.addByte((c0 << 2) | (c1 >> 4));
      out.addByte(((c1 & 0xf) << 4) | (c2 >> 2));
    } else if (rem == 2) {
      final c0 = idx[data[i]]!, c1 = idx[data[i + 1]]!;
      out.addByte((c0 << 2) | (c1 >> 4));
    }
    return out.toBytes();
  }

  /// algo 4 — XTEA variant (16-byte key, delta 0x481EAE9D, 32 rounds).
  static const int _xteaDelta = 0x481EAE9D;

  static List<int> _xteaEncBlock(List<int> k, int v0, int v1) {
    var s = 0;
    for (var i = 0; i < 32; i++) {
      s = (s - _xteaDelta) & _m32;
      v0 =
          (v0 +
              (((k[0] + ((v1 << 5) & _m32)) & _m32) ^
                  (k[1] + (v1 >> 3)) ^
                  (v1 + s))) &
          _m32;
      v1 =
          (v1 +
              (((k[2] + ((v0 << 5) & _m32)) & _m32) ^
                  (s + v0) ^
                  (k[3] + (v0 >> 3)))) &
          _m32;
    }
    return <int>[v0, v1];
  }

  static List<int> _xteaDecBlock(List<int> k, int v0, int v1) {
    var s = (-32 * _xteaDelta) & _m32;
    for (var i = 0; i < 32; i++) {
      v1 =
          (v1 -
              (((k[2] + ((v0 << 5) & _m32)) & _m32) ^
                  (s + v0) ^
                  (k[3] + (v0 >> 3)))) &
          _m32;
      v0 =
          (v0 -
              (((k[0] + ((v1 << 5) & _m32)) & _m32) ^
                  (s + v1) ^
                  (k[1] + (v1 >> 3)))) &
          _m32;
      s = (s + _xteaDelta) & _m32;
    }
    return <int>[v0, v1];
  }

  static Uint8List _algo4(List<int> key, List<int> data, {required bool dec}) {
    final k = _readU32beList(key, 0, 4);
    final out = BytesBuilder(copy: false);
    final input = dec ? data : _pkcs7Pad(data, 8);
    for (var i = 0; i < input.length; i += 8) {
      var v0 = _readU32be(input, i);
      var v1 = _readU32be(input, i + 4);
      final r = dec ? _xteaDecBlock(k, v0, v1) : _xteaEncBlock(k, v0, v1);
      out.add(_u32be(r[0]));
      out.add(_u32be(r[1]));
    }
    final raw = out.toBytes();
    return dec ? _pkcs7Unpad(raw, 8) : raw;
  }

  /// algo 5 — ChaCha variant (44-byte key = 32B key + 12B nonce, counter 1).
  static const List<int> _chaC = <int>[
    0x6967416d,
    0x48432063,
    0x61684341,
    0x754f5220,
  ];

  static void _chaQr(List<int> x, int a, int b, int cc, int d) {
    x[a] = (x[a] + x[b]) & _m32;
    x[d] = _rotl32(x[d] ^ x[a], 15);
    x[cc] = (x[cc] + x[d]) & _m32;
    x[b] = _rotl32(x[b] ^ x[cc], 11);
    x[a] = (x[a] + x[b]) & _m32;
    x[d] = _rotl32(x[d] ^ x[a], 9);
    x[cc] = (x[cc] + x[d]) & _m32;
    x[b] = _rotl32(x[b] ^ x[cc], 6);
  }

  static Uint8List _chachaBlock(List<int> key44, int counter) {
    final kw = _readU32leList(key44, 0, 8);
    final nw = _readU32leList(key44, 32, 3);
    final x = <int>[..._chaC, ...kw, counter, ...nw];
    final init = List<int>.from(x);
    for (var r = 0; r < 10; r++) {
      _chaQr(x, 0, 4, 8, 12);
      _chaQr(x, 1, 5, 9, 13);
      _chaQr(x, 2, 6, 10, 14);
      _chaQr(x, 3, 7, 11, 15);
      _chaQr(x, 0, 5, 10, 15);
      _chaQr(x, 1, 6, 11, 12);
      _chaQr(x, 2, 7, 8, 13);
      _chaQr(x, 3, 4, 9, 14);
    }
    final out = Uint8List(64);
    for (var i = 0; i < 16; i++) {
      _writeU32le(out, i * 4, (x[i] + init[i]) & _m32);
    }
    return out;
  }

  static Uint8List _algo5(List<int> key, List<int> data) {
    final out = Uint8List(data.length);
    var ctr = 1;
    for (var i = 0; i < data.length; i += 64) {
      final ks = _chachaBlock(key, ctr);
      ctr = (ctr + 1) & _m32;
      final end = (i + 64 < data.length) ? i + 64 : data.length;
      for (var j = i; j < end; j++) {
        out[j] = data[j] ^ ks[j - i];
      }
    }
    return out;
  }

  /// algo 6 — Blowfish variant B with the sample's custom P/S boxes.
  static int _bfF(List<List<int>> s, int x) {
    var v = (s[0][(x >> 24) & 0xff] + s[1][(x >> 16) & 0xff]) & _m32;
    v = (v ^ s[2][(x >> 8) & 0xff]) & _m32;
    return (v + s[3][x & 0xff]) & _m32;
  }

  static List<int> _bfRounds(List<int> p, List<List<int>> s, int l, int r) {
    for (var i = 0; i < 16; i++) {
      l = (l ^ p[i]) & _m32;
      r = (r ^ _bfF(s, l)) & _m32;
      final t = l;
      l = r;
      r = t;
    }
    final t = l;
    l = r;
    r = t;
    return <int>[l, r];
  }

  static List<int> _bfEncBlockFull(List<int> p, List<List<int>> s, int l, int r) {
    final v = _bfRounds(p, s, l, r);
    return <int>[(v[0] ^ p[17]) & _m32, (v[1] ^ p[16]) & _m32];
  }

  static (List<int>, List<List<int>>) _bfKeySchedule(List<int> key16) {
    final p = List<int>.from(kBfP);
    final s = <List<int>>[
      for (var b = 0; b < 4; b++) List<int>.from(kBfS.sublist(b * 256, b * 256 + 256)),
    ];
    for (var i = 0; i < 18; i++) {
      var w = 0;
      for (var t = 0; t < 4; t++) {
        w = ((w << 8) | key16[(i * 4 + t) % key16.length]) & _m32;
      }
      p[i] = (p[i] ^ w) & _m32;
    }
    var l = 0, r = 0;
    for (var i = 0; i < 18; i += 2) {
      final v = _bfEncBlockFull(p, s, l, r);
      l = v[0];
      r = v[1];
      p[i] = l;
      p[i + 1] = r;
    }
    for (var b = 0; b < 4; b++) {
      for (var i = 0; i < 256; i += 2) {
        final v = _bfEncBlockFull(p, s, l, r);
        l = v[0];
        r = v[1];
        s[b][i] = l;
        s[b][i + 1] = r;
      }
    }
    return (p, s);
  }

  static Uint8List _algo6(List<int> key, List<int> data, {required bool dec}) {
    final ks = _bfKeySchedule(key);
    final p = ks.$1;
    final s = ks.$2;
    final out = BytesBuilder(copy: false);
    if (!dec) {
      final padded = _pkcs7Pad(data, 8);
      for (var i = 0; i < padded.length; i += 8) {
        final v = _bfEncBlockFull(
          p,
          s,
          _readU32be(padded, i),
          _readU32be(padded, i + 4),
        );
        out.add(_u32be(v[0]));
        out.add(_u32be(v[1]));
      }
      return out.toBytes();
    }
    for (var i = 0; i < data.length; i += 8) {
      var l = _readU32be(data, i + 4) ^ p[16];
      var r = _readU32be(data, i) ^ p[17];
      for (var round = 15; round >= 0; round--) {
        final newL = r ^ p[round];
        final newR = l ^ _bfF(s, r);
        l = newL & _m32;
        r = newR & _m32;
      }
      out.add(_u32be(l));
      out.add(_u32be(r));
    }
    return _pkcs7Unpad(out.toBytes(), 8);
  }

  // ----------------------------------------------------------------- cascade

  static Uint8List cascade(
    List<int> data,
    List<EsdkZoneEntry> entries, {
    bool dec = false,
  }) {
    var buf = Uint8List.fromList(data);
    final list = dec ? entries.reversed.toList() : entries;
    for (final e in list) {
      final spec = kAlgoTable[e.selector];
      if (spec == null) throw StateError('unknown selector 0x${e.selector.toRadixString(16)}');
      final algo = spec[0];
      final klen = spec[1];
      if (klen != 0 && e.key.length != klen) {
        throw StateError('selector 0x${e.selector.toRadixString(16)} needs $klen bytes');
      }
      buf = switch (algo) {
        1 => _algo1(e.key, buf, dec: dec),
        2 => _algo2(e.key, buf),
        3 => _algo3(buf, dec: dec),
        4 => _algo4(e.key, buf, dec: dec),
        5 => _algo5(e.key, buf),
        6 => _algo6(e.key, buf, dec: dec),
        _ => throw StateError('unknown algorithm $algo'),
      };
    }
    return buf;
  }

  // -------------------------------------------------------------- wire codec

  static (int, Uint8List) _packCt(
    List<int> pt,
    List<EsdkZoneEntry> entries,
  ) {
    if (pt.length <= kChunkSize) {
      return (0, cascade(pt, entries));
    }
    final parts = <Uint8List>[];
    for (var i = 0; i < pt.length; i += kChunkSize) {
      final end = (i + kChunkSize < pt.length) ? i + kChunkSize : pt.length;
      final blk = cascade(pt.sublist(i, end), entries);
      parts.add(_u32be(blk.length));
      parts.add(blk);
    }
    final ct = BytesBuilder(copy: false)
      ..add(_kChunkMagic)
      ..add(_u32be(kChunkSize))
      ..add(_u32be(parts.length ~/ 2));
    for (final p in parts) {
      ct.add(p);
    }
    return (1, ct.toBytes());
  }

  static Uint8List _unpackCt(
    int chunked,
    List<int> ct,
    List<EsdkZoneEntry> entries,
  ) {
    if (chunked == 0) {
      return cascade(ct, entries, dec: true);
    }
    for (var i = 0; i < 4; i++) {
      if (ct[i] != _kChunkMagic[i]) throw StateError('bad chunk magic');
    }
    final count = _readU32be(ct, 8);
    var off = 12;
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      final len = _readU32be(ct, off);
      off += 4;
      out.add(cascade(ct.sublist(off, off + len), entries, dec: true));
      off += len;
    }
    return out.toBytes();
  }

  /// Encrypt [plaintext] into a v3 wire.
  ///
  /// [entries] must be ordered like the derived code and carry random keys of
  /// exactly the required lengths.
  static Uint8List encrypt({
    required List<int> key,
    required List<int> plaintext,
    required List<EsdkZoneEntry> entries,
    required int timeSeconds,
    int nodeCount = 0,
  }) {
    final raw = deriveCode(key, timeSeconds, nodeCount);
    final sels = raw.sublist(1);
    if (entries.length != sels.length) {
      throw StateError('zone entry count mismatch');
    }
    for (var i = 0; i < sels.length; i++) {
      if (entries[i].selector != sels[i]) {
        throw StateError('zone selectors must match code');
      }
    }
    final code = maskCode(key, timeSeconds, raw);
    final zone = BytesBuilder(copy: false);
    for (final e in entries) {
      zone.add(_u16be(e.key.length));
      zone.add(e.key);
    }
    final packed = _packCt(plaintext, entries);
    final prefix = BytesBuilder(copy: false)
      ..addByte(3)
      ..addByte(packed.$1)
      ..add(_u64be(slotOf(timeSeconds)))
      ..addByte(code.length)
      ..add(code)
      ..add(_u16be(zone.length))
      ..add(zone.toBytes())
      ..add(packed.$2);
    final prefixBytes = prefix.toBytes();
    final mac = _hmac(key, <int>[..._kSaltIntegrity, ...prefixBytes]);
    final wire = BytesBuilder(copy: false)
      ..add(prefixBytes)
      ..add(mac);
    return wire.toBytes();
  }

  /// Decrypt a v3 wire produced by the client or the server.
  static Uint8List decrypt({
    required List<int> key,
    required List<int> wire,
    List<int>? codeSalt,
  }) {
    if (wire.length < 32 + 12) throw StateError('wire too short');
    final slot = _readU64be(wire, 2);
    final clen = wire[10];
    final code = wire.sublist(11, 11 + clen);
    final raw = _unmaskCode(key, slot, code, codeSalt ?? _kSaltCode);
    final sels = raw.sublist(1);
    final p = wire.sublist(11 + clen);
    final wlen = _readU16be(p, 0);
    final zone = p.sublist(2, 2 + wlen);
    final entries = <EsdkZoneEntry>[];
    var off = 0;
    while (off < zone.length) {
      final len = _readU16be(zone, off);
      off += 2;
      entries.add(EsdkZoneEntry(sels[entries.length], Uint8List.fromList(zone.sublist(off, off + len))));
      off += len;
    }
    final ctEnd = p.length - 32;
    final ct = p.sublist(2 + wlen, ctEnd);
    final mac = p.sublist(ctEnd);
    final prefix = wire.sublist(0, wire.length - 32);
    final expect = _hmac(key, <int>[..._kSaltIntegrity, ...prefix]);
    if (!_equal(expect, mac)) throw StateError('final MAC mismatch');
    return _unpackCt(wire[1], ct, entries);
  }

  // ----------------------------------------------------------------- helpers

  static Uint8List _u16be(int v) => Uint8List.fromList(<int>[(v >> 8) & 0xff, v & 0xff]);

  static Uint8List _u32be(int v) => Uint8List.fromList(<int>[
    (v >> 24) & 0xff,
    (v >> 16) & 0xff,
    (v >> 8) & 0xff,
    v & 0xff,
  ]);

  // Division-based packing keeps 64-bit values exact under dart2js, where
  // bitwise shifts are limited to 32 bits.
  static Uint8List _u64be(int v) {
    final out = Uint8List(8);
    var rest = v;
    for (var i = 7; i >= 0; i--) {
      out[i] = rest % 256;
      rest = rest ~/ 256;
    }
    return out;
  }

  static int _readU16be(List<int> b, int o) => ((b[o] << 8) | b[o + 1]) & 0xffff;

  static int _readU32be(List<int> b, int o) =>
      ((b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]) & _m32;

  static int _readU64be(List<int> b, int o) {
    var v = 0;
    for (var i = 0; i < 8; i++) {
      v = v * 256 + b[o + i];
    }
    return v;
  }

  static List<int> _readU32beList(List<int> b, int o, int n) =>
      <int>[for (var i = 0; i < n; i++) _readU32be(b, o + i * 4)];

  static List<int> _readU32leList(List<int> b, int o, int n) =>
      <int>[for (var i = 0; i < n; i++) (b[o + i * 4] | (b[o + i * 4 + 1] << 8) | (b[o + i * 4 + 2] << 16) | (b[o + i * 4 + 3] << 24)) & _m32];

  static void _writeU32le(Uint8List b, int o, int v) {
    b[o] = v & 0xff;
    b[o + 1] = (v >> 8) & 0xff;
    b[o + 2] = (v >> 16) & 0xff;
    b[o + 3] = (v >> 24) & 0xff;
  }

  static Uint8List _pkcs7Pad(List<int> data, int bs) {
    final n = bs - data.length % bs;
    return Uint8List.fromList(<int>[...data, ...List<int>.filled(n, n)]);
  }

  static Uint8List _pkcs7Unpad(List<int> data, int bs) {
    if (data.isEmpty) return Uint8List(0);
    final b = data.last;
    if (b < 1 || b > bs || data.length < b) return Uint8List.fromList(data);
    for (var i = data.length - b; i < data.length; i++) {
      if (data[i] != b) return Uint8List.fromList(data);
    }
    return Uint8List.fromList(data.sublist(0, data.length - b));
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

String esdkHex(List<int> data) =>
    data.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List esdkUnhex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
