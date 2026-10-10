import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/modules/collect/collect_type.dart';
import 'package:kazumi/presentation/modern/calendar/modern_calendar_controller.dart';
import 'package:kazumi/services/calendar/calendar_models.dart';

ScheduleEntry entry(int id, int? day, String country) => parseScheduleEntry({
  'id': id,
  'name': '番剧 $id',
  'metaTags': [country],
}, weekday: day);

void main() {
  test('详情批处理未提交时刷新，新的放送时间仍能更新', () async {
    final controller = ModernCalendarController(
      clock: () => DateTime(2026, 10, 11),
      load: (season, {required force, required cancelToken}) async =>
          SeasonScheduleSnapshot(season: season, entries: [entry(1, 3, '日本')]),
      enrich: (value, {required force, required cancelToken}) async =>
          value.withDetail({
            'infobox': [
              {'key': '放送时间', 'value': '21:00 北京时间'},
            ],
          }),
      readCollections: () => {},
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    controller.queueDetail(controller.snapshot!.entries.single);
    await Future<void>.delayed(Duration.zero);
    await controller.refresh();
    controller.queueDetail(controller.snapshot!.entries.single);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(controller.snapshot!.entries.single.time, '21:00');
  });

  test('北京时间跨日规范化只执行一次，重复显示卡片不会继续移动星期', () async {
    var calls = 0;
    final controller = ModernCalendarController(
      clock: () => DateTime(2026, 10, 11),
      load: (season, {required force, required cancelToken}) async =>
          SeasonScheduleSnapshot(season: season, entries: [entry(1, 3, '日本')]),
      enrich: (value, {required force, required cancelToken}) async {
        calls++;
        return value.withDetail({
          'infobox': [
            {'key': '放送时间', 'value': '00:30 日本时间'},
          ],
        });
      },
      readCollections: () => {},
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    controller.queueDetail(controller.snapshot!.entries.single);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    controller.queueDetail(controller.snapshot!.entries.single);
    await Future<void>.delayed(const Duration(milliseconds: 220));
    expect(controller.snapshot!.entries.single.weekday, 2);
    expect(calls, 1);
  });
  test('快速切季只接纳最后一次结果，旧请求完成不覆盖新选择', () async {
    final first = Completer<SeasonScheduleSnapshot>();
    final second = Completer<SeasonScheduleSnapshot>();
    final controller = ModernCalendarController(
      clock: () => DateTime(2026, 10, 11),
      load: (season, {required force, required cancelToken}) =>
          season.month == 10 ? first.future : second.future,
      readCollections: () => {},
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    final old = controller.refresh();
    final latest = controller.selectSeason(DateTime(2026, 7));
    second.complete(
      SeasonScheduleSnapshot(
        season: DateTime(2026, 7),
        entries: [entry(2, 7, '中国')],
      ),
    );
    await latest;
    first.complete(
      SeasonScheduleSnapshot(
        season: DateTime(2026, 10),
        entries: [entry(1, 7, '日本')],
      ),
    );
    await old;
    expect(controller.season.month, 7);
    expect(controller.dayEntries().single.item.id, 2);
  });

  test('收藏事件同步筛选，未知地区和未知星期不混入日漫/周日', () async {
    final changes = StreamController<void>.broadcast(sync: true);
    final collections = <int, CollectType>{1: CollectType.watching};
    final controller = ModernCalendarController(
      clock: () => DateTime(2026, 10, 11),
      load: (season, {required force, required cancelToken}) async =>
          SeasonScheduleSnapshot(
            season: season,
            entries: [entry(1, 7, '日本'), entry(2, 7, '中国'), entry(3, null, '')],
          ),
      readCollections: () => Map.of(collections),
      collectionChanges: changes.stream,
      readHistory: () => [],
    );
    addTearDown(() async {
      controller.dispose();
      await changes.close();
    });
    await controller.refresh();
    expect(controller.dayEntries().length, 2);
    expect(controller.pendingEntries.single.item.id, 3);
    await controller.setFilters(watchingOnly: true);
    expect(controller.dayEntries().single.item.id, 1);
    collections[2] = CollectType.watching;
    changes.add(null);
    expect(controller.dayEntries().length, 2);
    await controller.setFilters(region: ScheduleRegion.japanese);
    expect(controller.dayEntries().single.item.id, 1);
  });

  test('刷新失败保留成功列表，合法空日历不显示网络失败', () async {
    var fail = false;
    final controller = ModernCalendarController(
      clock: () => DateTime(2026, 10, 11),
      load: (season, {required force, required cancelToken}) async {
        if (fail) throw Exception('offline');
        return SeasonScheduleSnapshot(
          season: season,
          entries: [entry(1, 7, '日本')],
        );
      },
      readCollections: () => {},
      readHistory: () => [],
    );
    addTearDown(controller.dispose);
    await controller.refresh();
    fail = true;
    await controller.refresh();
    expect(controller.dayEntries().single.item.id, 1);
    expect(controller.error, isNotNull);
    expect(controller.loading, isFalse);
  });
}
