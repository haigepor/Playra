import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_engine/response_backend.dart';

class _Backend implements LuminaResponseBackend {
  int calls = 0;
  ResponseBackendFailure? failure;
  Uint8List? plain;
  @override
  Uint8List decrypt(Uint8List raw, String path, Duration budget) {
    calls++;
    if (failure != null) throw failure!;
    return plain ?? Uint8List.fromList([1, 2, 3]);
  }
}

void main() {
  final raw = Uint8List.fromList([9]);
  const budget = Duration(seconds: 1);
  test(
    'business access rejection is delivered without retrying another decoder',
    () {
      final backend = _Backend()
        ..plain = Uint8List.fromList(
          utf8.encode('{"code":300400,"data":{"errCode":[10032]}}'),
        );
      final result = ResponseRouter(backend).decode(
        raw,
        '/app/video/play',
        budget,
        () => throw StateError('fallback'),
      );
      expect(jsonDecode(utf8.decode(result.plain))['code'], 300400);
      expect(result.backend, 'core');
    },
  );
  test('native result is preferred without calling fallback', () {
    final backend = _Backend();
    final result = ResponseRouter(
      backend,
    ).decode(raw, '/app/config', budget, () => throw StateError('fallback'));
    expect(result.plain, [1, 2, 3]);
    expect(result.backend, 'core');
    expect(backend.calls, 1);
  });
  test('timeout quarantines the backend before a later request', () {
    final backend = _Backend()
      ..failure = const ResponseBackendFailure('CORE_TIMEOUT', terminal: true);
    final router = ResponseRouter(backend);
    expect(router.decode(raw, '/', budget, () => raw).backend, 'fuse');
    backend.failure =
        null; // A late response must not make this backend usable again.
    expect(router.decode(raw, '/', budget, () => raw).plain, raw);
    expect(backend.calls, 1);
  });
  test('strict comparison never silently falls back', () {
    final backend = _Backend()
      ..failure = const ResponseBackendFailure('CORE_TIMEOUT', terminal: true);
    final router = ResponseRouter(backend, strict: true);
    for (var i = 0; i < 2; i++) {
      expect(
        () =>
            router.decode(raw, '/', budget, () => throw StateError('fallback')),
        throwsA(isA<ResponseBackendFailure>()),
      );
    }
    expect(backend.calls, 1);
  });
  test('one malformed reply does not disable later valid requests', () {
    final backend = _Backend()
      ..failure = const ResponseBackendFailure('CORE_REPLY');
    final router = ResponseRouter(backend);
    expect(router.decode(raw, '/', budget, () => raw).plain, raw);
    backend.failure = null;
    expect(router.decode(raw, '/', budget, () => raw).backend, 'core');
    expect(backend.calls, 2);
  });
  test('two consecutive non-terminal failures quarantine the backend', () {
    final backend = _Backend()
      ..failure = const ResponseBackendFailure('CORE_REPLY');
    final router = ResponseRouter(backend);
    expect(router.decode(raw, '/', budget, () => raw).backend, 'fuse');
    expect(router.decode(raw, '/', budget, () => raw).backend, 'fuse');
    // After 2 consecutive failures, backend is quarantined and won't be called again.
    backend.failure = null;
    expect(router.decode(raw, '/', budget, () => raw).backend, 'fuse');
    expect(backend.calls, 2);
  });
}
