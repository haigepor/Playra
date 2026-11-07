// ignore_for_file: avoid_print
// 红果源活体探针：Dart 移植层的端到端裁决。
// 运行：dart run tool/hongguo_live_probe.dart
// 验证：匿名设备注册（gzip+TTEncrypt）→ 签名请求 → 搜索/详情/分集 →
//       播放模型 + CENC 密钥推导 → CDN 可播性。
// 本机 flutter test 被原生资产工具链阻塞，协议层用纯 Dart 探针。
import 'dart:convert';
import 'dart:io';

import 'package:kazumi/services/source/hongguo/hongguo_client.dart';
import 'package:kazumi/services/source/hongguo/hongguo_device.dart';

int _step = 0;

void ok(String msg) {
  _step++;
  print('[$_step] OK  $msg');
}

void fail(String msg) {
  print('[$_step] FAIL $msg');
  exitCode = 1;
}

Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('hongguo_probe');
  final client = HongguoClient(
    profileStore: HongguoFileProfileStore(dir),
    retryAttempts: 3,
  );

  // 1) 搜索（首次调用触发匿名注册）
  final page = await client.search('离婚后，我成了全球最强');
  if (page.items.isEmpty) {
    fail('search returned no hits');
    return;
  }
  ok('search: ${page.items.length} hits, first="${page.items.first.title}" '
      'id=${page.items.first.id} eps=${page.items.first.episodeCount}');

  // 2) 详情 + 分集
  final (series, episodes) = await client.getSeries(page.items.first.id);
  ok('series: "${series.title}" eps=${episodes.length} '
      'cover=${series.coverUrl.isEmpty ? 'NONE' : series.coverUrl.substring(0, 40)}...');
  print('       ep1: id=${episodes.first.id} number=${episodes.first.number} '
      '"${episodes.first.title}"');

  // 3) 播放模型 + CENC 密钥（与 npm SDK 同集对比）
  final (pb, key) = await client.resolvePlayback(episodes.first.id);
  ok('playback: streams=${pb.streams.length} protected=${pb.protected} '
      'expires=${pb.expiresAt == 0 ? 'n/a' : DateTime.fromMillisecondsSinceEpoch(pb.expiresAt * 1000).toIso8601String()}');
  for (final s in pb.streams) {
    print('       ${s.definition} ${s.codec} ${s.width}x${s.height} '
        'enc=${s.encryption} url=${s.url.substring(0, 60)}...');
  }
  print('       contentKey=${key?.hex ?? 'NONE'} version=${key?.version ?? ''}');
  if (pb.protected && key == null) {
    fail('protected stream but no content key');
  }

  // 4) CDN 可播性（Range 拉首块，校验 mp4 头）
  final stream = pb.streams.firstWhere(
    (s) => s.url.isNotEmpty,
    orElse: () => throw StateError('no stream url'),
  );
  final hc = HttpClient();
  final req = await hc.getUrl(Uri.parse(stream.url))
    ..headers.set('Range', 'bytes=0-65535');
  final resp = await req.close();
  final body = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  final magic = body.length > 8 && utf8.decode(body.sublist(4, 8)) == 'ftyp';
  ok('cdn: status=${resp.statusCode} type=${resp.headers.contentType} '
      'range=${resp.headers.value('content-range')} ftyp=$magic (${body.length}B)');
  if (resp.statusCode != 206 || !magic) {
    fail('CDN range fetch did not return playable mp4 head');
  }
  hc.close();

  // 5) 首页频道数据面：榜单 / 书城推荐 / 热搜
  final rank = await client.shortRank();
  ok('shortRank: ${rank.items.length} rows, first="${rank.items.firstOrNull?.title}" '
      'contents=${rank.contents.length} boards=${rank.boards.length}');
  final discover = await client.discover();
  ok('discover: ${discover.page.items.length} items, more=${discover.page.hasMore}, '
      'next=${discover.next != null}');
  if (discover.next != null) {
    final page2 = await client.discover(next: discover.next);
    ok('discover page2: ${page2.page.items.length} more items');
  }
  final hot = await client.hotSearch();
  ok('hotSearch: guesses=${hot.guesses.length} boards=${hot.boards.length}');

  client.dispose();
  print('PROBE PASS');
}
