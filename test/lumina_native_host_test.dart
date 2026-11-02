import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/platform/lumina_support.dart';
import 'package:kazumi/services/source/lumina/lumina_executor.dart';
import 'package:kazumi/services/source/source_models.dart';

void main() {
  test(
    'public executor rejects invalid calls before assets or network initialization',
    () async {
      await expectLater(
        executeLumina('detail', {'videoId': '../invalid'}, null),
        throwsA(
          isA<SourceException>().having(
            (e) => e.code,
            'code',
            luminaSupported ? 'INVALID_ARGUMENT' : 'PLATFORM_UNSUPPORTED',
          ),
        ),
      );
      await expectLater(
        executeLumina('user', {}, null),
        throwsA(
          isA<SourceException>().having(
            (e) => e.code,
            'code',
            luminaSupported ? 'UNSUPPORTED' : 'PLATFORM_UNSUPPORTED',
          ),
        ),
      );
    },
  );
  test('pre-cancelled request cannot start native initialization', () async {
    final cancel = CancelToken()..cancel();
    await expectLater(
      executeLumina('channels', {}, cancel),
      throwsA(
        isA<SourceException>().having(
          (e) => e.code,
          'code',
          luminaSupported ? 'CANCELLED' : 'PLATFORM_UNSUPPORTED',
        ),
      ),
    );
  });
}
