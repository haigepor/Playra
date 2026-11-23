import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/clicli/clicli_models.dart';

void main() {
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

  test('count-only fallback remains available as release information', () {
    final detail = mediaDetailFromVideo({
      'id': 'unknown',
      'title': '作品',
      'updateSchedule': '共12集',
    });
    expect(detail.episodeStatus, '共12集');
    expect(detail.updateSchedule, isEmpty);
  });
}
