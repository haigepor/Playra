import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/player/cast_eligibility.dart';

void main() {
  String? check({
    String url = 'https://example.test/video.m3u8?token=private',
    bool local = false,
    String referer = '',
    bool headers = false,
  }) => castUnavailableReason(
    isLocalPlayback: local,
    url: url,
    referer: referer,
    hasPlaybackHeaders: headers,
  );

  test('only remotely fetchable header-free sources can be cast', () {
    expect(check(), isNull);
    expect(check(url: 'http://192.168.1.2/video'), isNull);
    expect(check(local: true), isNotNull);
    expect(check(referer: 'https://origin.test'), isNotNull);
    expect(check(headers: true), isNotNull);
    expect(check(url: 'file:///private/video'), isNotNull);
    expect(check(url: 'https://user:secret@example.test/video'), isNotNull);
    expect(check(url: 'not a URL'), isNotNull);
  });

  test('unavailable messages do not expose URLs or request credentials', () {
    final message = check(
      url: 'https://example.test/video?token=private',
      referer: 'https://origin.test/?secret=value',
    );
    expect(message, isNot(contains('https://')));
    expect(message, isNot(contains('private')));
    expect(message, isNot(contains('secret')));
  });
}
