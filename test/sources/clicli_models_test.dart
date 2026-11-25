import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/clicli/clicli_models.dart';
import 'package:kazumi/features/sources/core/media_models.dart';

void main() {
  test('banner permits only absolute credential-free web links', () {
    MediaBanner banner(String link) =>
        MediaBanner(id: '1', title: '', imageUrl: '', linkUrl: link);
    expect(
      banner('https://example.com/offer').externalUri,
      Uri.parse('https://example.com/offer'),
    );
    for (final link in [
      '',
      '/relative',
      'javascript:alert(1)',
      'file:///etc/passwd',
      'https://name:secret@example.com',
    ]) {
      expect(banner(link).externalUri, isNull, reason: link);
    }
  });

  test('ongoing release count is not presented as a total or an alias', () {
    final video = <String, dynamic>{
      'id': 'live-ongoing',
      'title': '仙逆',
      'alias': 'Renegade Immortal',
      'currentEpisodes': 168,
      'totalEpisodes': 1,
      'isFinished': 0,
      'updateSchedule': '168|周日18:30后更',
    };
    final detail = mediaDetailFromVideo(video);
    final card = mediaItemFromVideo(video);
    expect(detail.episodeStatus, '更新至 168 集');
    expect(detail.subtitle, 'Renegade Immortal');
    expect(detail.updateSchedule, '周日18:30后更');
    expect(card.subtitle, detail.episodeStatus);
    expect(card.updateSchedule, detail.updateSchedule);
  });

  test(
    'finished releases keep the completed status out of scheduling metadata',
    () {
      final detail = mediaDetailFromVideo({
        'id': 'live-completed',
        'title': '地狱老师 Part.2',
        'currentEpisodes': 13,
        'totalEpisodes': 13,
        'isFinished': 1,
        'updateSchedule': '13集全',
      });
      expect(detail.episodeStatus, '全 13 集');
      expect(detail.updateSchedule, isEmpty);
    },
  );

  test('missing total remains unknown instead of using the page length', () {
    final page = mediaPageFromVideos({
      'videos': [
        {'id': 'one', 'title': '作品一'},
        {'id': 'two', 'title': '作品二'},
      ],
      'pageinfo': {'pageIndex': 1, 'pages': 3},
    });
    expect(page.items, hasLength(2));
    expect(page.total, 0);
    expect(page.hasMore, isTrue);
  });

  test('packed update schedule does not leak the internal separator', () {
    final item = mediaItemFromVideo({
      'id': 'one',
      'title': '作品',
      'updateSchedule': '168|周日18:30后更',
    });
    expect(item.subtitle, '周日18:30后更');
  });

  test('count-only fallback remains available as release information', () {
    final detail = mediaDetailFromVideo({
      'id': 'unknown',
      'title': '作品',
      'updateSchedule': '共12集',
    });
    expect(detail.episodeStatus, '共12集');
    expect(detail.updateSchedule, isEmpty);
  });

  test('distinct posterUrl is preserved as fallbackCover', () {
    final item = mediaItemFromVideo({
      'id': 'cover-fallback',
      'title': '作品',
      'coverUrl': 'https://broken.example.com/a.jpg',
      'posterUrl': 'https://pic7.iqiyipic.com/image/b.jpg',
    });
    expect(item.cover, 'https://broken.example.com/a.jpg');
    expect(item.fallbackCover, 'https://pic7.iqiyipic.com/image/b.jpg');

    final same = mediaItemFromVideo({
      'id': 'cover-same',
      'title': '作品2',
      'coverUrl': 'https://pic7.iqiyipic.com/image/b.jpg',
      'posterUrl': 'https://pic7.iqiyipic.com/image/b.jpg',
    });
    expect(same.fallbackCover, isEmpty);
  });
}
