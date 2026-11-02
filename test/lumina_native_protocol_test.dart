import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_engine/client.dart';
import 'package:lumina_engine/primitives.dart';
import 'package:kazumi/services/storage/sdk_library_models.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';

void main() {
  test('CB64 preserves UTF-8 and padding', () {
    final bytes = utf8.encode('动漫 第 01 集');
    expect(uncb64(cb64(bytes)), bytes);
    expect(uncb64(cb64(bytes).replaceAll('=', '')), bytes);
    expect(unpad(pad(bytes)), bytes);
    expect(() => unpad(List.filled(16, 0)), throwsFormatException);
  });
  test('AES core matches the NIST AES-128 vector', () {
    final aes = Aes128(hexBytes('2b7e151628aed2a6abf7158809cf4f3c'));
    expect(
      aes.decrypt(hexBytes('3ad77bb40d7a3660a89ecaf32466ef97')),
      hexBytes('6bc1bee22e409f96e93d7e117393172a'),
    );
  });
  test('long plaintext JSON containing dots is not an encrypted envelope', () {
    final plain = jsonEncode({'code': 20000, 'data': '${'x' * 400}.png'});
    expect(splitEnvelope(plain), isNull);
    final cipher = '${cb64(List.filled(256, 1))}.${cb64(List.filled(16, 2))}';
    expect(splitEnvelope(cipher)!.$1, List.filled(256, 1));
    expect(splitEnvelope(cipher)!.$2, List.filled(16, 2));
    expect(splitEnvelope('${'x' * 344}.!invalid!'), isNull);
  });
  test('resolver accepts plaintext, hex, CB64 and standard base64 AES-CBC', () {
    const key = '0123456789abcdef', iv = 'fedcba9876543210';
    const cipher =
        'a0ee288813982981d76aa3b862703e59519ba8196aa21cd0be72cde3eca78d46254ba09d670cd41bc6a0ea0be32bebee';
    const expected = {'url': 'https://cdn.example.com/a.mp4'};
    for (final value in [
      jsonEncode(expected),
      cipher,
      cb64(hexBytes(cipher)),
      base64Encode(hexBytes(cipher)),
    ]) {
      expect(parseResolver(value, key, iv), expected);
    }
    expect(
      () => parseResolver(cipher, '0000000000000000', iv),
      throwsA(isA<LuminaFailure>()),
    );
  });
  test('only seven operations and bounded arguments are accepted', () {
    expect(() => validatePayload('user', {}), throwsA(isA<LuminaFailure>()));
    expect(
      () => validatePayload('config', {'url': 'https://example.com'}),
      throwsA(isA<LuminaFailure>()),
    );
    expect(
      () => validatePayload('catalog', {'channelId': '1', 'pageSize': 101}),
      throwsA(isA<LuminaFailure>()),
    );
    expect(
      () => validatePayload('search', {'keyword': ' '}),
      throwsA(isA<LuminaFailure>()),
    );
    expect(validatePayload('search', {'keyword': ' 动漫 '})['keyword'], '动漫');
    expect(
      validatePayload('play', {
        'videoId': '1',
        'playFormat': 'mp4',
        'part': ' 第01集 ',
      })['part'],
      ' 第01集 ',
    );
  });
  test('source episode names remain stable identities', () {
    final detail = normalize('detail', {
      'id': 42,
      'name': '作品',
      'parts': [
        {
          'play': 'mp4',
          'part': ['第01集', '特别篇 上'],
        },
      ],
    }, {});
    final episodes = (detail['parts'] as List).first['episodes'] as List;
    expect(episodes.map((dynamic e) => e['part']), ['第01集', '特别篇 上']);
    expect(episodes.map((dynamic e) => e['index']), [1, 2]);
  });
  test(
    'description normalization strips markup and preserves HTML entities as text',
    () {
      final detail = normalize('detail', {
        'id': 42,
        'name': '作品',
        'content': '<p>A &amp; B&nbsp;&lt;特别篇&gt;</p>',
        'parts': [],
      }, {});
      expect(detail['video']['summary'], 'A & B\u00a0<特别篇>');
    },
  );
  test('media URL validation rejects local destinations and credentials', () {
    for (final url in [
      'file:///tmp/x',
      'http://127.0.0.1/a',
      'http://10.1.1.1/a',
      'http://[::1]/a',
      'http://user:pass@example.com/a',
      'http://video.local/a',
    ]) {
      expect(() => validatePublicUri(url), throwsA(isA<LuminaFailure>()));
    }
    expect(
      validatePublicUri('https://cdn.example.com/video.mp4').host,
      'cdn.example.com',
    );
    final links = directLinks({
      'url': 'https://cdn.example.com/video.mp4',
      'type': 'mp4',
    });
    expect(links.first['headers']['User-Agent'], '');
  });
  test(
    'removed provider history retains identity, collection and progress',
    () {
      final progress = SdkWatchProgress(
        episode: const SdkEpisode(
          number: 1,
          name: '第01集',
          code: 'mp4',
          reference: '第01集',
        ),
        position: const Duration(seconds: 123),
        duration: const Duration(minutes: 24),
        updatedAt: DateTime(2026, 10, 19),
      );
      final record = SdkLibraryRecord(
        providerId: 'miomedia',
        contentId: '42',
        title: '旧作品',
        collectionType: 2,
        collectedAt: DateTime(2026, 10, 18),
        lastWatch: progress,
        progresses: {progress.key: progress},
      );
      final restored = SdkLibraryRecord.fromJson(
        jsonDecode(jsonEncode(record.toJson())),
      );
      expect(restored.toJson(), record.toJson());
      expect(restored.lastWatch!.position.inSeconds, 123);
      expect(restored.sourceName, contains('记录保留'));
    },
  );
}
