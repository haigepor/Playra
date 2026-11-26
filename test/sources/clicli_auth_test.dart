import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kazumi/features/sources/clicli/clicli_client.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/clicli/clicli_auth.dart';
import 'package:kazumi/features/sources/clicli/clicli_config.dart';
import 'package:kazumi/features/sources/core/media_source.dart';

const testPublicKey =
    'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLr3V8V4xviYZcvH1UhIPD4uzEX4HuFoNYrOJlNGodWeNjlBvz7B6PcFHGd6nlWrD+ymeA5wG6qKDb5Lfqfp2BglA8wZjOw0//XRijssMkx3KE84sG1Lt/OBe2wEfsvYYmVI//klCtwPCkjwhqgLADKuBG6RZQlVbsH7iXbeFXAQIDAQAB';

class MemoryStore implements CliCliSessionStore {
  Map<String, dynamic>? value;
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> session) async {
    value = Map.of(session);
  }

  @override
  Future<void> clear() async {
    value = null;
  }
}

class AuthAdapter implements HttpClientAdapter {
  int refreshes = 0;
  final seen = <String?>[];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancel,
  ) async {
    final Map<String, Object> reply;
    if (options.path == CliCliConfig.pathRefreshToken) {
      refreshes++;
      reply = {
        'code': 200,
        'data': {'token': 'new', 'refreshToken': 'r2'},
      };
    } else {
      final token = options.headers['Authorization'] as String?;
      seen.add(token);
      reply = token == 'Bearer new'
          ? {
              'code': 200,
              'data': {'ok': true},
            }
          : {'code': 4012};
    }
    return ResponseBody.fromString(
      jsonEncode(reply),
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

BigInt number(String value) =>
    base64.decode(value).fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));

void main() {
  test(
    'login encrypts password using server RSA key and persists tokens only',
    () async {
      const pub =
          'MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDLr3V8V4xviYZcvH1UhIPD4uzEX4HuFoNYrOJlNGodWeNjlBvz7B6PcFHGd6nlWrD+ymeA5wG6qKDb5Lfqfp2BglA8wZjOw0//XRijssMkx3KE84sG1Lt/OBe2wEfsvYYmVI//klCtwPCkjwhqgLADKuBG6RZQlVbsH7iXbeFXAQIDAQAB';
      const n =
          'y691fFeMb4mGXLx9VISDw+LsxF+B7haDWKziZTRqHVnjY5Qb8+wej3BRxnep5Vqw/spngOcBuqig2+S36n6dgYJQPMGYzsNP/10Yo7LDJMdyhPOLBtS7fzgXtsBH7L2GJlSP/5JQrcDwpI8IaoCwAyrgRukWUJVW7B+4l23hVwE=';
      const d =
          'OvLJxrWzwCgGCdrHTumXFN8c9OxLNzOuycAnOXEE8P+tzojz2hFQ+uRf1leVhPpNVUAQ2n6AwpvBCkLUc3o3bNqNMYOJA5nwCcME2d1wcEkG069SZM8XcbQPTAnq6AQqXRW+Fdeh7aI4i16BT+DHKL411pycky5X/AmW/DiPno0=';
      final store = MemoryStore();
      final auth = CliCliAuth(
        (path, payload) async {
          if (path.endsWith('/encryptKey')) {
            return {
              'publicKey':
                  '-----BEGIN PUBLIC KEY-----\n$pub\n-----END PUBLIC KEY-----',
            };
          }
          expect(path, endsWith('/login'));
          var clear = number(
            payload['password'] as String,
          ).modPow(number(d), number(n));
          final bytes = List<int>.filled(128, 0);
          for (var i = 127; i >= 0; i--) {
            bytes[i] = (clear & BigInt.from(255)).toInt();
            clear >>= 8;
          }
          expect(bytes.take(2), [0, 2]);
          final end = bytes.indexOf(0, 2);
          expect(end, greaterThanOrEqualTo(10));
          expect(utf8.decode(bytes.sublist(end + 1)), 'test-only-password');
          expect(payload['account'], 'example');
          return {'token': 'access', 'refreshToken': 'refresh'};
        },
        store: store,
        account: 'example',
        password: 'test-only-password',
      );
      await auth.initialize();
      expect(auth.token, 'access');
      expect(store.value, {
        'account': 'example',
        'token': 'access',
        'refreshToken': 'refresh',
      });
      expect(store.value.toString(), isNot(contains('test-only-password')));
    },
  );

  test('parallel and late stale refreshes rotate once and persist', () async {
    final store = MemoryStore()
      ..value = {'account': 'example', 'token': 'old', 'refreshToken': 'r1'};
    final gate = Completer<void>();
    var requests = 0;
    final auth = CliCliAuth(
      (path, payload) async {
        expect(path, CliCliConfig.pathRefreshToken);
        expect(payload['refreshToken'], 'r1');
        requests++;
        await gate.future;
        return {'token': 'new', 'refreshToken': 'r2'};
      },
      store: store,
      account: 'example',
      password: 'dummy',
    );
    await auth.initialize();
    final a = auth.refresh('old');
    final b = auth.refresh('old');
    gate.complete();
    expect(await Future.wait([a, b]), [true, true]);
    expect(await auth.refresh('old'), isTrue);
    expect(requests, 1);
    expect(store.value!['refreshToken'], 'r2');
    final restored = CliCliAuth(
      (_, _) async => throw StateError('unexpected request'),
      store: store,
      account: 'example',
      password: 'dummy',
    );
    await restored.initialize();
    expect(restored.token, 'new');
    await restored.clear();
    expect(store.value, isNull);
  });

  test(
    'expired refresh triggers one shared login; network failure does not',
    () async {
      final store = MemoryStore()
        ..value = {'account': 'example', 'token': 'old', 'refreshToken': 'r1'};
      final gate = Completer<void>();
      var logins = 0;
      final auth = CliCliAuth(
        (path, payload) async {
          if (path == CliCliConfig.pathRefreshToken) {
            await gate.future;
            throw const MediaSourceException(
              MediaSourceErrorKind.authentication,
              'expired',
              code: 4013,
            );
          }
          if (path.endsWith('/encryptKey')) {
            return {
              'publicKey':
                  '-----BEGIN PUBLIC KEY-----\n$testPublicKey\n-----END PUBLIC KEY-----',
            };
          }
          logins++;
          return {'token': 'new', 'refreshToken': 'r2'};
        },
        store: store,
        account: 'example',
        password: 'dummy',
      );
      await auth.initialize();
      final first = auth.refresh('old');
      final second = auth.refresh('old');
      gate.complete();
      expect(await Future.wait([first, second]), [true, true]);
      expect(logins, 1);
      expect(store.value!['token'], 'new');

      var calls = 0;
      final network = CliCliAuth(
        (_, _) async {
          calls++;
          throw const MediaSourceException(
            MediaSourceErrorKind.network,
            'offline',
          );
        },
        store: store,
        account: 'example',
        password: 'dummy',
      );
      await network.initialize();
      await expectLater(
        network.refresh('new'),
        throwsA(isA<MediaSourceException>()),
      );
      expect(calls, 1);
    },
  );

  test('client sends bearer and retries 4012 with rotated token', () async {
    final store = MemoryStore()
      ..value = {'account': 'example', 'token': 'old', 'refreshToken': 'r1'};
    final adapter = AuthAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    addTearDown(() => dio.close(force: true));
    final client = CliCliClient(
      dio: dio,
      sessionStore: store,
      account: 'example',
      password: 'dummy',
    );
    expect(await client.callData('/test', {}), {'ok': true});
    expect(adapter.seen, ['Bearer old', 'Bearer new']);
    expect(adapter.refreshes, 1);
    expect(store.value!['refreshToken'], 'r2');
  });

  test('no credentials leaves anonymous and does not touch storage', () async {
    final auth = CliCliAuth(
      (_, _) async => throw StateError('unexpected request'),
      store: MemoryStore(),
    );
    await auth.initialize();
    expect(auth.token, isNull);
  });
}
