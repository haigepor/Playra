import 'dart:convert';
import 'dart:io';
import 'package:lumina_engine/lumina_engine.dart';
import 'package:lumina_engine/primitives.dart';

void check(bool ok, String message) {
  if (!ok) throw StateError(message);
}

void main(List<String> args) {
  if (args.length < 3) {
    throw ArgumentError(
      'fixture.json profile.json image.bin [more-vectors.json]',
    );
  }
  final f = jsonDecode(File(args[0]).readAsStringSync()) as Map;
  final p = jsonDecode(File(args[1]).readAsStringSync()) as Map;
  final engine = LuminaEngine(args[2]);
  final key = hexBytes(f['key']), plain = hexBytes(f['plain']);
  check(cb64(uncb64('5iW7')) == '5iW7', 'CB64');
  check(
    base64Encode(Aes128(key).f(List.filled(16, 0))) ==
        base64Encode(hexBytes(f['f'])),
    'F vector',
  );
  final encrypted = engine.encrypt(key, pad(plain));
  print(
    'native request bytes=${encrypted.length}; expected=${hexBytes(f['cipher']).length}; prefix=${base64Encode(encrypted.take(16).toList()) == base64Encode(hexBytes(f['cipher']).take(16).toList())}',
  );
  check(
    base64Encode(encrypted) == base64Encode(hexBytes(f['cipher'])),
    'request encryption',
  );
  check(
    base64Encode(engine.decrypt(key, hexBytes(f['cipher']))) ==
        base64Encode(plain),
    'response decrypt',
  );
  final s =
      '${p['CODE_VERSION']}-${f['authTs']}-Android-${p['APP_VERSION']}-${f['fp']}-${p['CLIENT_CATEGORY']}';
  final a1 = ascii.encode(cb64(ascii.encode(s)));
  check(
    cb64(engine.auth(hexBytes(p['_AUTH_KEY']), hexBytes(p['_AUTH_IV']), a1)) ==
        f['auth'],
    'authentication',
  );
  final private = RsaKey.privateDer(base64Decode(p['_SERVER_PRIV_B64']));
  check(
    base64Encode(private.decrypt(hexBytes(f['p0']))) == base64Encode(key),
    'RSA response',
  );
  check(
    RsaKey.publicDer(base64Decode(p['_SERVER_PUB_B64'])).encrypt(key).length ==
        256,
    'RSA request',
  );
  final aes = Aes128(hexBytes('2b7e151628aed2a6abf7158809cf4f3c'));
  check(
    base64Encode(aes.decrypt(hexBytes('3ad77bb40d7a3660a89ecaf32466ef97'))) ==
        base64Encode(hexBytes('6bc1bee22e409f96e93d7e117393172a')),
    'NIST AES',
  );
  try {
    unpad(List.filled(16, 0));
    throw StateError('bad padding accepted');
  } on FormatException {
    /* expected */
  }
  if (args.length > 3) {
    final more = jsonDecode(File(args[3]).readAsStringSync()) as Map;
    for (final vector in more['cases']) {
      final key = hexBytes(vector['key']),
          plain = hexBytes(vector['plain']),
          cipher = hexBytes(vector['cipher']);
      check(
        base64Encode(engine.encrypt(key, pad(plain))) == base64Encode(cipher),
        'block encrypt vector',
      );
      check(
        base64Encode(engine.decrypt(key, cipher)) == base64Encode(plain),
        'block decrypt vector',
      );
    }
    for (final vector in more['auths']) {
      final s =
          '${p['CODE_VERSION']}-${vector['ts']}-Android-${p['APP_VERSION']}-${vector['fp']}-${p['CLIENT_CATEGORY']}';
      final a1 = ascii.encode(cb64(ascii.encode(s)));
      check(
        cb64(
              engine.auth(
                hexBytes(p['_AUTH_KEY']),
                hexBytes(p['_AUTH_IV']),
                a1,
              ),
            ) ==
            vector['value'],
        'auth vector',
      );
    }
    print(
      'PASS: 11 block encrypt/decrypt vectors and 3 authentication vectors',
    );
  }
  print('PASS: 8 protocol/native checks; engine=${engine.version}');
}
