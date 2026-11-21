// Golden-vector + round-trip regression for the esdk-v3 Dart port.
//
//   cd tool/clicli/protocol_check && dart run bin/check.dart [vectorDir]
//
// Default vectorDir is the CliCli RE reference directory. The 34 vectors were
// captured from the device oracle; matching them proves the port is byte-exact.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as c;

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/protocol/esdk_v3.dart';

const String _sessionSecret = String.fromEnvironment(
  'CLICLI_TEST_SESSION_SECRET',
);

var _pass = 0;
var _fail = 0;
final List<String> _failures = <String>[];

void _check(String name, bool ok, [String? detail]) {
  if (ok) {
    _pass++;
  } else {
    _fail++;
    _failures.add(detail == null ? name : '$name :: $detail');
  }
}

Uint8List _u16(int v) => Uint8List.fromList(<int>[(v >> 8) & 0xff, v & 0xff]);

Uint8List _u64(int v) {
  final out = Uint8List(8);
  var rest = v;
  for (var i = 7; i >= 0; i--) {
    out[i] = rest % 256;
    rest = rest ~/ 256;
  }
  return out;
}

String _hex(List<int> data) => esdkHex(data);

void main(List<String> args) {
  final dir = args.isNotEmpty
      ? args.first
      : 'D:/project-Auto/CliCli动漫/dm-client';
  final key = Uint8List.fromList(ascii.encode(_sessionSecret));

  for (final file in <String>['_vec8.json', '_vec9.json']) {
    final f = File('$dir/$file');
    if (!f.existsSync()) {
      stderr.writeln('missing vector file: ${f.path}');
      exitCode = 2;
      return;
    }
    final vectors = jsonDecode(f.readAsStringSync()) as List<dynamic>;
    for (var i = 0; i < vectors.length; i++) {
      _checkVector('$file#$i', key, vectors[i] as Map<String, dynamic>);
    }
  }

  _roundTrips();
  _chunkedEnvelope(key);

  stdout.writeln('PASS $_pass  FAIL $_fail');
  for (final f in _failures.take(20)) {
    stdout.writeln('  FAIL $f');
  }
  if (_fail != 0) exitCode = 1;
}

void _checkVector(String id, Uint8List key, Map<String, dynamic> v) {
  final t = v['t'] as int;
  final nc = v['nc'] as int;
  final chunked = v['chunked'] as int;
  final codeHex = v['code'] as String;
  final wlen = v['wlen'] as int;
  final pt = esdkUnhex(v['pt'] as String);
  final ctHex = v['ct'] as String;
  final macHex = v['mac'] as String;

  final raw = EsdkV3.deriveCode(key, t, nc);
  _check('$id code', _hex(EsdkV3.maskCode(key, t, raw)) == codeHex,
      '${_hex(EsdkV3.maskCode(key, t, raw))} != $codeHex');
  final sels = raw.sublist(1);

  final entsJson = v['ents'] as List<dynamic>;
  _check('$id selCount', sels.length == entsJson.length,
      '${sels.length} != ${entsJson.length}');
  final entries = <EsdkZoneEntry>[];
  for (var j = 0; j < entsJson.length; j++) {
    final e = entsJson[j] as List<dynamic>;
    final len = e[0] as int;
    final kb = esdkUnhex(e[1] as String);
    _check('$id keylen$j', kb.length == len, '${kb.length} != $len');
    entries.add(EsdkZoneEntry(sels[j], kb));
  }

  final zone = BytesBuilder(copy: false);
  for (final e in entries) {
    zone.add(_u16(e.key.length));
    zone.add(e.key);
  }
  _check('$id wlen', zone.length == wlen, '${zone.length} != $wlen');

  final ct = EsdkV3.cascade(pt, entries);
  _check('$id ct', _hex(ct) == ctHex, '${_hex(ct)} != $ctHex');
  if (chunked == 1) {
    _check('$id chunkMagic',
        _hex(ct.sublist(0, 4)) == '4543534d', _hex(ct.sublist(0, 4)));
  }

  final prefix = BytesBuilder(copy: false)
    ..addByte(3)
    ..addByte(chunked)
    ..add(_u64(t ~/ 3600))
    ..addByte(esdkUnhex(codeHex).length)
    ..add(esdkUnhex(codeHex))
    ..add(_u16(zone.length))
    ..add(zone.toBytes())
    ..add(ct);
  final prefixBytes = prefix.toBytes();
  final mac = c.Hmac(c.sha256, key)
      .convert(<int>[...ascii.encode('payload-integrity'), ...prefixBytes])
      .bytes;
  _check('$id mac', _hex(mac) == macHex, '${_hex(mac)} != $macHex');

  final wire = <int>[...prefixBytes, ...mac];
  final back = EsdkV3.decrypt(key: key, wire: wire);
  _check('$id decrypt', _hex(back) == _hex(pt), '${_hex(back)} != ${_hex(pt)}');

  final enc = EsdkV3.encrypt(
    key: key,
    plaintext: pt,
    entries: entries,
    timeSeconds: t,
    nodeCount: nc,
  );
  _check('$id encrypt', _hex(enc) == _hex(wire),
      'len ${enc.length} != ${wire.length}');
}

void _roundTrips() {
  const sizes = <int>[0, 1, 7, 8, 9, 15, 16, 17, 63, 64, 65, 255, 4096];
  final rng = Random(20261114);
  final keys = <int, Uint8List>{
    0x19: _bytes(rng, 16),
    0x3b: _bytes(rng, 44),
    0x75: _bytes(rng, 16),
    0x82: Uint8List(0),
    0x9a: _bytes(rng, 16),
    0xe4: _bytes(rng, 8),
  };
  for (final sel in keys.keys) {
    for (final n in sizes) {
      final data = _bytes(rng, n);
      final entries = <EsdkZoneEntry>[EsdkZoneEntry(sel, keys[sel]!)];
      final enc = EsdkV3.cascade(data, entries);
      final dec = EsdkV3.cascade(enc, entries, dec: true);
      _check('rt 0x${sel.toRadixString(16)} n=$n', _hex(dec) == _hex(data));
    }
  }
}

void _chunkedEnvelope(Uint8List key) {
  const t = 1762600000;
  final raw = EsdkV3.deriveCode(key, t);
  final rng = Random(7);
  final entries = <EsdkZoneEntry>[];
  const table = <int, int>{0x19: 16, 0x3b: 44, 0x75: 16, 0x82: 0, 0x9a: 16, 0xe4: 8};
  for (final sel in raw.sublist(1)) {
    entries.add(EsdkZoneEntry(sel, _bytes(rng, table[sel]!)));
  }
  final pt = Uint8List(200000);
  for (var i = 0; i < pt.length; i++) {
    pt[i] = i & 0xff;
  }
  final wire = EsdkV3.encrypt(
    key: key,
    plaintext: pt,
    entries: entries,
    timeSeconds: t,
  );
  _check('chunked flag', wire[1] == 1, 'flag=${wire[1]}');
  final back = EsdkV3.decrypt(key: key, wire: wire);
  _check('chunked roundtrip', _hex(back) == _hex(pt),
      'len ${back.length} != ${pt.length}');
}

Uint8List _bytes(Random rng, int n) {
  final out = Uint8List(n);
  for (var i = 0; i < n; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}
