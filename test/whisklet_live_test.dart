import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:kazumi/services/source/whisklet/whisklet_catalog.dart';
import 'package:kazumi/services/source/whisklet/whisklet_home_controller.dart';
import 'package:kazumi/services/source/whisklet/whisklet_models.dart';
import 'package:kazumi/services/source/whisklet/whisklet_playback_provider.dart';

/// 真连验收（默认跳过）：上游是活的第三方站点，端点形态或加密信封可能轮换。
/// 运行：`flutter test test/whisklet_live_test.dart --dart-define=WHISKLET_LIVE=true`
/// （`bool.fromEnvironment` 只认 `true` 字面量。）
void main() {
  const live = bool.fromEnvironment('WHISKLET_LIVE');
  if (!live) {
    test(
      'whisklet live probe skipped (set --dart-define=WHISKLET_LIVE=true)',
      () {
        markTestSkipped('真连验收需显式开启');
      },
    );
    return;
  }

  final catalog = WhiskletCatalog();
  tearDownAll(catalog.close);

  test('七个风格频道都出片，动漫优先源之外仍有片单', () async {
    for (final style in HomeStyle.values) {
      final page = await catalog.browse(style.tid, 1);
      expect(
        page.items,
        isNotEmpty,
        reason: '${style.label}(tid=${style.tid}) 应返回片单',
      );
      expect(page.items.first.identity, startsWith('whisklet:'));
      expect(page.pages, greaterThan(0));
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('热门由 5 个榜单分类合成并跨分类去重', () async {
    final items = await catalog.hot();
    expect(items.length, greaterThan(20));
    expect(items.map((work) => work.id).toSet().length, items.length);
    // 交错合并：首 5 条必须来自不同分类，而不是一个分类连续占满。
    final head = items.take(5).map((work) => work.categoryId).toSet();
    expect(head.length, greaterThan(1));
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('推荐分栏带栏名与片目', () async {
    final shelves = await catalog.shelves();
    expect(shelves, isNotEmpty);
    expect(shelves.first.title, isNotEmpty);
    expect(shelves.first.items.length, greaterThan(6));
    expect(shelves.every((shelf) => shelf.title.isNotEmpty), isTrue);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('详情线路可解析出选集表', () async {
    final page = await catalog.browse(HomeStyle.series.tid, 1);
    final lines = await catalog.lines(page.items.first.id);
    expect(lines, isNotEmpty, reason: '至少一条线路');
    expect(lines.first.code, isNotEmpty);
    expect(lines.first.episodes, isNotEmpty);
    expect(lines.first.episodes.first.token, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('控制器按频道加载并可续页', () async {
    // 控制器拥有自己的目录与连接，避免与共用 catalog 的用例相互关闭。
    final source = WhiskletHomeController();
    addTearDown(source.dispose);
    await source.loadStyle(HomeStyle.shortDrama);
    expect(source.of(HomeStyle.shortDrama), isNotEmpty);
    expect(source.failed(HomeStyle.shortDrama), isFalse);
    final first = source.of(HomeStyle.shortDrama).length;
    if (source.hasMore(HomeStyle.shortDrama)) {
      await source.loadMore(HomeStyle.shortDrama);
      expect(source.of(HomeStyle.shortDrama).length, greaterThan(first));
    }
  }, timeout: const Timeout(Duration(seconds: 120)));

  test('片目字段可用于首页卡片', () async {
    final work = (await catalog.browse(HomeStyle.movie.tid, 1)).items.first;
    expect(work.title, isNotEmpty);
    expect(work.cover, anyOf(isEmpty, startsWith('http')));
    expect(WhiskletWork.plain('<b>标题</b>&amp;副题'), '标题&副题');
  }, timeout: const Timeout(Duration(seconds: 60)));

  /// 在几个频道里找一条指定形态的线路（parseApi 为空 = 直链）。
  Future<(WhiskletWork, WhiskletLine)?> findLine(
    bool Function(WhiskletLine) predicate,
  ) async {
    for (final tid in [
      HomeStyle.series.tid,
      HomeStyle.movie.tid,
      HomeStyle.anime.tid,
      HomeStyle.shortDrama.tid,
    ]) {
      final page = await catalog.browse(tid, 1);
      for (final item in page.items.take(5)) {
        for (final line in await catalog.lines(item.id)) {
          if (line.episodes.isNotEmpty && predicate(line)) {
            return (item, line);
          }
        }
      }
    }
    return null;
  }

  test('直链线 playEpisode 返回可播 m3u8', () async {
    final found = await findLine((line) => line.parseApi.isEmpty);
    expect(found, isNotNull, reason: '样本集中应存在直链线路');
    final (work, line) = found!;
    final provider = WhiskletPlaybackProvider(catalog);
    addTearDown(provider.dispose);
    final episodes = await provider.episodes('${work.id}', line.code);
    expect(episodes, isNotEmpty);
    expect(episodes.first.reference, isNotEmpty);
    final result = await provider.playEpisode(
      '${work.id}',
      line.code,
      episodes.first,
    );
    expect(result['status'], 'ready');
    final url = (result['media'] as Map)['url'] as String;
    // 直链令牌本身就是播放地址：裸 GET 应 200 且是 m3u8 清单。
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 20));
    expect(response.statusCode, 200);
    expect(utf8.decode(response.bodyBytes), contains('#EXTM3U'));
  }, timeout: const Timeout(Duration(seconds: 180)));

  test('家族线 param 换直链（配额满时如实报 UPSTREAM_LIMIT）', () async {
    final found = await findLine(
      (line) => line.parseApi.contains('/ajiami/'),
    );
    expect(found, isNotNull, reason: '样本集中应存在 ajiami 家族线路');
    final (work, line) = found!;
    final provider = WhiskletPlaybackProvider(catalog);
    addTearDown(provider.dispose);
    final episodes = await provider.episodes('${work.id}', line.code);
    final result = await provider.playEpisode(
      '${work.id}',
      line.code,
      episodes.first,
    );
    if (result['status'] == 'ready') {
      final url = (result['media'] as Map)['url'] as String;
      expect(Uri.parse(url).scheme, isIn(['http', 'https']));
    } else {
      // 2026-11-03 实测：上游解析后端有日点数配额，403=配额满，
      // 协议层通过判据是 param 满长（provider 内部已完成）。
      expect(result['error'], 'UPSTREAM_LIMIT');
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
