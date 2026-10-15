import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/source_resolve_config.dart';

void main() {
  test(
    'replace suppresses inherited credentials but keeps explicit media headers',
    () {
      final media =
          SourceResolveConfig({
            'request': {'url': 'https://runtime.example/resolve'},
          }).parse(
            '{"url":"https://media.example/video","headers":{"User-Agent":"sdk"},"headerPolicy":"replace"}',
          );
      expect(media.inheritHeaders, isFalse);
      expect(
        media.effectiveHeaders({
          'referer': 'https://site.example',
          'cookie': 'private',
        }),
        {'User-Agent': 'sdk'},
      );
    },
  );
  test('old API rules continue merging default headers', () {
    final media =
        SourceResolveConfig({
          'request': {'url': 'https://runtime.example/resolve'},
        }).parse(
          '{"url":"https://media.example/video","headers":{"referer":"new"}}',
        );
    expect(media.effectiveHeaders({'referer': 'old', 'user-agent': 'ua'}), {
      'referer': 'new',
      'user-agent': 'ua',
    });
  });
}
