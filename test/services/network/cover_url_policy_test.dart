import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/cover_url_policy.dart';

void main() {
  setUp(CoverUrlPolicy.clearFailedCache);

  test('normalizes whitespace, protocol-relative URLs, and HTTPS CDNs', () {
    expect(CoverUrlPolicy.normalize('  '), '');
    expect(CoverUrlPolicy.normalize('ftp://example.com/a.jpg'), '');
    expect(
      CoverUrlPolicy.normalize(' //pic6.iqiyipic.com/image/2026/a.jpg '),
      'https://pic6.iqiyipic.com/image/2026/a.jpg',
    );
    expect(
      CoverUrlPolicy.normalize('http://img1.doubanio.com/view/photo/l/p1.jpg'),
      'https://img1.doubanio.com/view/photo/l/p1.jpg',
    );
  });

  test('rewrites retired qnmob and JS-challenged img9 Douban hosts', () {
    expect(
      CoverUrlPolicy.normalize(
        'https://qnmob3.doubanio.com/view/photo/large/public/p2910702194.jpg?imageView2/0/q/80/w/9999/h/120/format/jpg',
      ),
      'https://img2.doubanio.com/view/photo/large/public/p2910702194.jpg',
    );
    expect(
      CoverUrlPolicy.normalize(
        'https://img9.doubanio.com/view/photo/s_ratio_poster/public/p2910702194.jpg',
      ),
      'https://img2.doubanio.com/view/photo/s_ratio_poster/public/p2910702194.jpg',
    );
  });

  test('routes Referer per CDN domain so non-Douban CDNs are not 403ed', () {
    final doubanHeaders = CoverUrlPolicy.headersFor(
      'https://img2.doubanio.com/view/photo/l/public/p1.jpg',
    );
    expect(doubanHeaders['Referer'], 'https://movie.douban.com/');
    expect(doubanHeaders['User-Agent'], isNotEmpty);

    final iqiyiHeaders = CoverUrlPolicy.headersFor(
      'https://pic7.iqiyipic.com/image/20261029/80/c2/a_101729722.jpg',
    );
    expect(iqiyiHeaders.containsKey('Referer'), isFalse);
    expect(iqiyiHeaders['User-Agent'], isNotEmpty);

    final biliHeaders = CoverUrlPolicy.headersFor(
      'https://i0.hdslb.com/bfs/archive/abc.jpg',
    );
    expect(biliHeaders['Referer'], 'https://www.bilibili.com/');
  });

  test('negative cache remembers failures until TTL or proxy revision change', () {
    const url = 'https://img2.doubanio.com/view/photo/l/public/missing.webp';
    final baseTime = DateTime(2026, 11, 25, 16, 0, 0);

    expect(CoverUrlPolicy.isRecentlyFailed(url, now: baseTime), isFalse);
    CoverUrlPolicy.markFailed(url, now: baseTime);
    expect(
      CoverUrlPolicy.isRecentlyFailed(
        url,
        now: baseTime.add(const Duration(minutes: 5)),
      ),
      isTrue,
    );

    // Proxy / network configuration change clears failure memory immediately.
    NetworkConfig.revision++;
    expect(
      CoverUrlPolicy.isRecentlyFailed(
        url,
        now: baseTime.add(const Duration(minutes: 5)),
      ),
      isFalse,
    );

    CoverUrlPolicy.markFailed(url, now: baseTime);
    expect(
      CoverUrlPolicy.isRecentlyFailed(
        url,
        now: baseTime.add(const Duration(minutes: 11)),
      ),
      isFalse,
    );
  });
}
