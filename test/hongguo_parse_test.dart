// 红果协议解析形状测试：以活体响应观察到的结构为准（2026-11-07 采集）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/hongguo/hongguo_parse.dart';

void main() {
  test('search tab keeps series rows and offsets', () {
    final page = parseSearchTab(jsonDecode(_searchFixture), 11);
    expect(page, isNotNull);
    expect(page!.items, hasLength(2));
    expect(page.items.first.id, '7436384826061491262');
    expect(page.items.first.title, '开局离婚后成为了最强大佬');
    expect(page.items.first.episodeCount, 80);
    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 20);
  });

  test('video_detail derives 1-based numbering and synthesizes titles', () {
    final parsed = parseSeries(jsonDecode(_seriesFixture));
    expect(parsed, isNotNull);
    final (series, episodes) = parsed!;
    expect(series.id, '7436384826061491262');
    expect(series.coverUrl, contains('fqnovelpic.com'));
    expect(episodes, hasLength(3));
    // vid_index 从 0 开始时整体平移为 1 起。
    expect(episodes.first.number, 1);
    // 标题被简介复制时按集数命名。
    expect(episodes.first.title, '第1集');
    expect(episodes[1].id, '7436597320885472319');
    expect(episodes[2].title, '回家');
  });

  test('video_model parses streams, protection and wrapped key material', () {
    final pb = parsePlayback(jsonDecode(_playbackFixture), '7436597320885472318');
    expect(pb, isNotNull);
    final playback = pb!;
    expect(playback.videoId, '7194887290266044');
    expect(playback.protected, isTrue);
    expect(playback.streams, hasLength(2));
    expect(playback.streams.last.definition, '720p');
    expect(playback.streams.last.height, 1280);
    expect(playback.streams.last.encryption, 'cenc-aes-ctr');
    expect(playback.keyMaterial, 'KgoQAQ==');
    expect(playback.expiresAt, 1794000000);
  });

  test('video_list as object map yields sorted definition keys', () {
    final pb = parsePlayback(jsonDecode(_playbackMapFixture), '1');
    expect(pb, isNotNull);
    expect(pb!.streams.map((s) => s.definition).toList(), ['360p', '720p']);
  });

  test('bookmall recommend tab unwraps nested cells', () {
    final page = parseDiscoverTab(jsonDecode(_discoverFixture), 16);
    expect(page, isNotNull);
    expect(page!.items, hasLength(2));
    expect(page.items.first.title, '布衣枭雄第一季');
    expect(page.items.first.coverUrl, contains('fqnovelpic.com'));
    final cont = discoverContinuation(jsonDecode(_discoverFixture), 16);
    expect(cont, isNotNull);
    expect(cont!.sessionId, 'S1');
    expect(cont.cellId, '7294257141911650341');
  });

  test('business codes classify into retryable/content kinds', () {
    expect(classifyCode(100, '{}'), HongguoErrorKind.rateLimited);
    expect(classifyCode(101104, '书籍不存在'), HongguoErrorKind.contentGone);
    expect(classifyCode(101, 'ALL_CONTENT_SHOWN'), HongguoErrorKind.endOfList);
    expect(classifyCode(111, '需要验证'), HongguoErrorKind.challenge);
    expect(classifyCode(4000, ''), HongguoErrorKind.param);
  });

  test('register envelope requires both ids', () {
    expect(
      parseRegister({'device_id_str': '7100000000000011',
          'install_id_str': '7100000000000012', 'new_user': 1}),
      isNotNull,
    );
    expect(
      parseRegister({'device_id_str': '0', 'install_id_str': '1'}),
      isNull,
    );
    expect(parseRegister({'device_id_str': '71000'}), isNull);
  });
}

const _searchFixture = '''
{"code":0,"message":"SUCCESS","search_tabs":[
  {"tab_type":11,"has_more":true,"next_offset":20,"data":[
    {"video_data":[{"series_id":"7436384826061491262","video_detail":{
      "series_title":"开局离婚后成为了最强大佬","series_intro":"安逸成从小智商超于常人",
      "series_cover":"https://p3-reading-sign.fqnovelpic.com/novel-pic/2d4f?x-expires=1799000000","episode_cnt":80}},
      {"series_id":"7566630916202695742","video_detail":{"series_title":"为师的爱徒人设，千万不能崩！","series_intro":"","series_cover":"","episode_cnt":169}}]}]}]}
''';

const _seriesFixture = '''
{"code":0,"message":"SUCCESS","data":{"video_data":{
  "series_id_str":"7436384826061491262","series_title":"开局离婚后成为了最强大佬",
  "series_intro":"简介","series_cover":"https://p3-reading-sign.fqnovelpic.com/novel-pic/2d4f?x-expires=1799000000",
  "episode_cnt":3,"series_status":0,
  "video_list":[
    {"vid":"7436597320885472318","vid_index":0,"title":"简介","disable_play":false,
     "series_id":"7436384826061491262","duration":302},
    {"vid":"7436597320885472319","vid_index":1,"title":"简介","disable_play":false,
     "series_id":"7436384826061491262","duration":300},
    {"vid":"7436597320885472320","vid_index":2,"title":"回家","disable_play":false,
     "series_id":"7436384826061491262","duration":299}
  ]}}}
''';

const _playbackFixture =
    '{"code":0,"message":"SUCCESS","data":{"video_model":"{'
    '\\"video_id\\":\\"7194887290266044\\",\\"media_type\\":\\"video\\",'
    '\\"video_duration\\":302.4,\\"url_expire\\":1794000000,\\"video_list\\":['
    '{\\"definition\\":\\"360p\\",\\"codec_type\\":\\"bytevc1\\",\\"vwidth\\":360,\\"vheight\\":640,'
    '\\"bitrate\\":284531,\\"main_url\\":\\"https://v95-sz-reading-video.qznovelvod.com/a1\\",'
    '\\"backup_url\\":\\"https://backup.example/a1\\",\\"encrypt_info\\":{'
    '\\"encrypt\\":true,\\"encryption_method\\":\\"cenc-aes-ctr\\",\\"spade_a\\":\\"KgoQAQ==\\"}},'
    '{\\"definition\\":\\"720p\\",\\"codec_type\\":\\"bytevc1\\",\\"vwidth\\":720,\\"vheight\\":1280,'
    '\\"bitrate\\":548346,\\"main_url\\":\\"https://v95-sz-reading-video.qznovelvod.com/a2\\",'
    '\\"encrypt_info\\":{\\"encrypt\\":true,\\"encryption_method\\":\\"cenc-aes-ctr\\",'
    '\\"spade_a\\":\\"KgoQAQ==\\"}}'
    ']}"}}';

const _playbackMapFixture = '''
{"code":0,"message":"SUCCESS","data":{"video_model":{"video_id":"1","url_expire":0,
  "video_list":{
    "720p":{"definition":"720p","main_url":"https://cdn.example/720"},
    "360p":{"definition":"360p","main_url":"https://cdn.example/360"}}}}}
''';

const _discoverFixture = '''
{"code":0,"message":"SUCCESS","data":{"tab_item":[
  {"tab_type":45,"has_more":false,"cell_data":[]},
  {"tab_type":16,"has_more":true,"session_id":"S1","client_template":2,"cell_data":[
    {"cell_id_str":"7294257141911650341","show_type":407,"cell_data":[
      {"show_type":407,"video_data":[
        {"series_id":"7685820017287367742","video_detail":{
          "series_title":"布衣枭雄第一季","series_intro":"宋小川穿越到古代",
          "series_cover":"https://p3-reading-sign.fqnovelpic.com/novel-pic/61c3?x-expires=1799181381",
          "episode_cnt":500}}]},
      {"show_type":407,"video_data":[
        {"series_id":"7436384826061491262","video_detail":{
          "series_title":"开局离婚后成为了最强大佬","series_intro":"",
          "series_cover":"","episode_cnt":80}}]}
    ]}
  ]}
]}}
''';
