import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';
import 'package:kazumi/services/calendar/calendar_service.dart';

Map<String, dynamic> subject(int id, {String region = '日本'}) => {
  'id': id,
  'name': '番剧 $id',
  'metaTags': [region, 'TV'],
  'rating': {'score': 8.1, 'total': 10},
};

void main() {
  test('接口星期覆盖模型默认值，缺图条目保留，同日去重而跨日保留', () {
    final result = parseCalendarSnapshot({
      '1': [
        {'subject': subject(1), 'watchers': 20},
        {'subject': subject(1), 'watchers': 20},
      ],
      '3': [
        {'subject': subject(1), 'watchers': 20},
      ],
    }, season: DateTime(2026, 10));
    expect(result.entries.map((e) => e.weekday), [1, 3]);
    expect(result.entries.first.item.images, isEmpty);
    expect(result.entries.first.watchers, 20);
  });

  test('历史搜索没有明确星期时进入待定，不用首播日期推算', () {
    final entry = parseScheduleEntry({...subject(2), 'date': '2026-07-04'});
    expect(entry.weekday, isNull);
    expect(entry.item.airWeekday, 0);
  });

  test('明确日本时区与跨日时刻换算为北京时间', () {
    final entry = parseScheduleEntry(subject(3), weekday: 6).withDetail({
      'infobox': [
        {'key': '放送时间', 'value': '每周六 24:30（日本时间）'},
      ],
    });
    expect(entry.weekday, 6);
    expect(entry.time, '23:30');
  });

  test('不明时区或多个放送时刻不猜测唯一时间', () {
    final entry = parseScheduleEntry(subject(3), weekday: 1);
    expect(
      entry.withDetail({
        'infobox': [
          {'key': '放送时间', 'value': '21:05'},
        ],
      }).time,
      isNull,
    );
    expect(
      entry.withDetail({
        'infobox': [
          {'key': '放送时间', 'value': '日本时间 21:05 / 23:00'},
        ],
      }).time,
      isNull,
    );
  });

  test('未知地区保留在全部，结构化地区识别不猜标题', () {
    expect(
      parseScheduleEntry(subject(4, region: '中国')).region,
      ScheduleRegion.chinese,
    );
    expect(
      parseScheduleEntry({...subject(5, region: ''), 'name': '日本故事'}).region,
      ScheduleRegion.unknown,
    );
  });

  test('无效整体响应报错，合法七日空日历不报网络失败', () {
    expect(
      () => parseCalendarSnapshot({
        'error': 'unavailable',
      }, season: DateTime(2026, 10)),
      throwsFormatException,
    );
    expect(
      parseCalendarSnapshot({
        for (var i = 1; i <= 7; i++) '$i': [],
      }, season: DateTime(2026, 10)).entries,
      isEmpty,
    );
  });

  test('历史季度按 total 获取超过 80 条，并保留未知星期', () async {
    final service = CalendarService(
      clock: () => DateTime(2026, 10, 11),
      useMirror: () => false,
      get: (url, {queryParameters, cancelToken}) async => {},
      post: (url, {data, queryParameters, cancelToken}) async {
        final offset = queryParameters!['offset'] as int;
        final filter = (data as Map)['filter'] as Map;
        expect(filter.containsKey('tag'), isFalse);
        expect(filter.containsKey('rank'), isFalse);
        return {
          'total': 85,
          'data': [
            for (var i = offset; i < (offset + 50).clamp(0, 85); i++)
              subject(i + 1),
          ],
        };
      },
    );
    final result = await service.load(DateTime(2026, 7));
    expect(result.entries.length, 85);
    expect(result.entries.every((e) => e.weekday == null), isTrue);
    expect(result.partial, isFalse);
  });

  test('季度缓存可复用，显式刷新重新取数', () async {
    var calls = 0;
    final service = CalendarService(
      clock: () => DateTime(2026, 10, 11),
      useMirror: () => false,
      get: (url, {queryParameters, cancelToken}) async {
        calls++;
        return {
          '1': [
            {'subject': subject(1)},
          ],
        };
      },
    );
    await service.load(DateTime(2026, 10));
    await service.load(DateTime(2026, 11));
    expect(calls, 1);
    await service.load(DateTime(2026, 10), force: true);
    expect(calls, 2);
  });
}
