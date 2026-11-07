/// 红果匿名协议的请求构建层（对标 openhongguo internal/protocol 的
/// app.go / request.go / register.go / tt_encrypt.go / device.go）。
/// 纯 Dart；查询参数顺序是签名的一部分，不得改动。
library;

import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

import 'hongguo_device.dart';
import 'hongguo_sign.dart' show hexEncode;

// ---------------------------------------------------------------------------
// 应用常量（app.go；com.phoenix.read 7.3.9.32 观察值）
// ---------------------------------------------------------------------------

const String hongguoPackage = 'com.phoenix.read';
const String hongguoVersionName = '7.3.9.32';
const String hongguoVersionCode = '73932';
const String hongguoAID = '8662';
const String hongguoAppName = 'novelread';
const String hongguoDevicePlatform = 'android';

const String hongguoApiHost = 'api5-normal-sinfonlinea.fqnovel.com';
const String hongguoRegisterHost = 'log5-applog-lq.fqnovel.com';

const String pathDiscover = '/reading/bookapi/bookmall/tab/v';
const String pathCellChange = '/reading/bookapi/bookmall/cell/change/v';
const String pathSearch = '/reading/bookapi/search/tab/v';
const String pathSeries = '/novel/player/video_detail/v1/';
const String pathSeriesBatch = '/novel/player/multi_video_detail/player/v1';
const String pathPlayback = '/novel/player/video_model/v1/';
const String pathAlbum = '/novel/player/album_detail/v1/';
const String pathSuggest = '/reading/bookapi/search/suggest/v1/';
const String pathCue = '/reading/bookapi/search/cue/v1/';
const String pathPlan = '/reading/bookapi/plan/v1/';
const String pathRegister = '/service/2/device_register/';

const String searchTabShortPlay = '11';
const String searchSourceHome = '1';
const String searchTabName = 'feed';

/// 短剧榜单页的 bookmall cell（tab_type 26）。
const String shortRankCell = '7470092475068071998';
const String shortRankActors = 'ranklist_celebrity';

/// 书城频道定义（channel.go）：请求 tab_type / 响应保留 tab_type / bottom_tab。
class HongguoDiscoverChannel {
  const HongguoDiscoverChannel({
    required this.name,
    required this.requestTab,
    required this.responseTab,
    required this.bottomTab,
  });

  final String name;
  final String requestTab;
  final int responseTab;
  final String bottomTab;
}

const hongguoChannelRecommend = HongguoDiscoverChannel(
  name: '推荐',
  requestTab: '-1',
  responseTab: 16,
  bottomTab: '7',
);
const hongguoChannelMotion = HongguoDiscoverChannel(
  name: '漫剧',
  requestTab: '36',
  responseTab: 36,
  bottomTab: '7',
);
const hongguoChannelLive = HongguoDiscoverChannel(
  name: '真人剧',
  requestTab: '39',
  responseTab: 39,
  bottomTab: '7',
);

/// UA 形如官方客户端的 Cronet 串；机型代号写进 UA。
String hongguoUserAgent(HongguoDevice device) {
  final d = device;
  return '$hongguoPackage/$hongguoVersionCode '
      '(Linux; U; Android ${d.osVersion}; zh_CN; ${d.model}; '
      'Build/${d.build}; Cronet/TTNetVersion:8d40f833 2026-03-03 '
      'QuicVersion:21ac1950 2025-11-18)';
}

/// 客户端的 x-reading-request：millis + '-' + abs(randomInt)。
String readingRequestID(int unixMillis, int randomInt) {
  final n = randomInt < 0 ? -randomInt : randomInt;
  return '$unixMillis-$n';
}

/// 媒体/封面 URL 的签名有效期（x-expires unix 秒）；无参数返回 null。
int? urlLifetime(String raw) {
  final idx = raw.indexOf('?');
  if (idx < 0) return null;
  for (final pair in raw.substring(idx + 1).split('&')) {
    final kv = pair.split('=');
    if (kv.length == 2 && kv[0] == 'x-expires') {
      final secs = int.tryParse(kv[1]);
      if (secs != null && secs > 0) return secs;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// 设备查询与业务 query（request.go）
// ---------------------------------------------------------------------------

/// 匿名设备查询；顺序是签名的一部分。
List<(String, String)> deviceQueryPairs(HongguoSearchIdentity id) {
  final d = id.device;
  final kind = d.pad ? 'pad' : 'phone';
  final pad = d.pad ? '1' : '0';
  return [
    ('iid', id.installId),
    ('device_id', id.deviceId),
    ('ac', 'wifi'),
    ('channel', d.channel),
    ('aid', hongguoAID),
    ('app_name', hongguoAppName),
    ('cdid', id.cdId),
    ('version_code', hongguoVersionCode),
    ('version_name', hongguoVersionName),
    ('device_platform', hongguoDevicePlatform),
    ('os', 'android'),
    ('ssmix', 'a'),
    ('device_type', d.model),
    ('device_brand', d.brand),
    ('language', 'zh'),
    ('os_api', '${d.osApi}'),
    ('os_version', d.osVersion),
    ('manifest_version_code', hongguoVersionCode),
    ('resolution', d.resolution),
    ('dpi', '${d.dpi}'),
    ('update_version_code', hongguoVersionCode),
    ('host_abi', 'arm64-v8a'),
    ('dragon_device_type', kind),
    ('pv_player', hongguoVersionCode),
    ('compliance_status', '0'),
    ('need_personal_recommend', '1'),
    ('player_so_load', '1'),
    ('is_android_pad_screen', pad),
    ('openudid', id.openUdId),
  ];
}

/// 搜索一页（综合 tab）。
List<(String, String)> signedSearchPairsFor(
  HongguoSearchIdentity id,
  String keyword, {
  int count = 20,
  int offset = 0,
  String tab = searchTabShortPlay,
}) {
  if (count <= 0) count = 20;
  if (offset < 0) offset = 0;
  return [
    ...deviceQueryPairs(id),
    ('query', keyword),
    ('tab_type', tab),
    ('count', '$count'),
    ('offset', '$offset'),
    ('use_correct', 'true'),
    ('bookshelf_search_plan', '4'),
    ('search_source', searchSourceHome),
    ('tab_name', searchTabName),
    ('bookstore_tab', '16'),
    ('user_is_login', '0'),
  ];
}

/// 书城频道一页（bottom_tab_type 7 = 短剧书城）。
List<(String, String)> signedDiscoverPairsIn(
  HongguoSearchIdentity id, {
  String tabType = '-1',
  String bottom = '7',
}) {
  if (tabType.isEmpty) tabType = '-1';
  return [
    ...deviceQueryPairs(id),
    ('tab_type', tabType),
    ('offset', '0'),
    ('client_req_type', '3'),
    ('bottom_tab_type', bottom),
    ('bottom_tab_type_list', '7,0,1,2,3,4'),
  ];
}

/// cell/change 无限流一页。
List<(String, String)> signedCellChangePairs(
  HongguoSearchIdentity id, {
  required String cellId,
  required String sessionId,
  required String showType,
  required String tabType,
  String clientTemplate = '',
  String offset = '0',
}) {
  if (offset.isEmpty) offset = '0';
  final pairs = <(String, String)>[
    ...deviceQueryPairs(id),
    ('cell_id', cellId),
    ('offset', offset),
    ('limit', '20'),
    ('change_type', '0'),
    ('tab_type', tabType),
    ('show_type', showType),
    ('client_req_type', '2'),
    ('session_id', sessionId),
  ];
  if (clientTemplate.isNotEmpty) {
    pairs.add(('client_template', clientTemplate));
  }
  return pairs;
}

/// 短剧榜单一页。
List<(String, String)> signedShortRankPairs(
  HongguoSearchIdentity id, {
  required String content,
  String list = '',
  int offset = 0,
  List<String> seen = const [],
  String session = '',
}) {
  final change = offset > 0 ? '2' : '1';
  final pairs = <(String, String)>[
    ...deviceQueryPairs(id),
    ('cell_id', shortRankCell),
    ('tab_type', '26'),
    ('selected_items', content),
  ];
  if (list.isNotEmpty) pairs.add(('sub_selected_items', list));
  pairs.addAll([
    ('offset', '$offset'),
    ('limit', '0'),
    ('client_req_type', '2'),
    ('client_template', '2'),
    ('unlimited_selector_change_type', change),
  ]);
  if (seen.isNotEmpty && content != shortRankActors) {
    pairs.add(('filter_ids', seen.join(',')));
  }
  if (session.isNotEmpty) pairs.add(('session_id', session));
  pairs.add(('user_is_login', '0'));
  return pairs;
}

/// 搜索页热搜（plan feed）。
List<(String, String)> signedHotSearchPairs(HongguoSearchIdentity id) {
  return [
    ...deviceQueryPairs(id),
    ('user_is_login', '0'),
    ('bookstore_tab', '16'),
    ('bookstore_tab_type', '16'),
    ('scene', '10'),
    ('limit', '0'),
    ('tab_name', searchTabName),
    ('from', 'search_input_page'),
    ('query_history_removed', 'false'),
    ('offset', '0'),
    ('search_middle_page_version', '4'),
    ('search_source', searchSourceHome),
    ('new_search_middle_page', 'true'),
    ('hot_word_exchange', 'false'),
  ];
}

/// 联想词。
List<(String, String)> signedSuggestPairs(HongguoSearchIdentity id, String keyword) {
  return [
    ...deviceQueryPairs(id),
    ('query', keyword),
    ('count', '10'),
    ('search_source', searchSourceHome),
    ('user_is_login', '0'),
  ];
}

// ---------------------------------------------------------------------------
// POST 请求体
// ---------------------------------------------------------------------------

String _jsonOf(Map<String, dynamic> v) => jsonEncode(v);

/// video_detail 请求体。
Uint8List seriesBody(String seriesId) {
  return utf8.encode(_jsonOf({
    'series_id': seriesId,
    'biz_param': {
      'caller_scene': 'single_col',
      'detail_page_version': 0,
      'from_video_id': '',
      'need_all_video_definition': false,
      'need_mp4_align': false,
      'source': 4,
      'video_id_type': 1,
    },
  }));
}

/// video_model 请求体。
Uint8List playbackBody(String episodeId) {
  return utf8.encode(_jsonOf({
    'video_id': episodeId,
    'biz_param': {
      'video_id_type': 0,
      'need_all_video_definition': true,
      'video_platform': 3,
    },
  }));
}

// ---------------------------------------------------------------------------
// 注册体（register.go + tt_encrypt.go）
// ---------------------------------------------------------------------------

final Uint8List _ttEncryptConstant = _decodeHex(
  '4dd4c2e6b83162090e52b3c7a6733ba41cb2462b829ab58a196b39db57177524f'
  '49baf7f08e8d68d26a72e37c1a95a2f1f05a51892aef2949732b62a38aadd58',
);
final Uint8List _ttEncryptPrefix = _decodeHex(
  '3176c9b6d71579d7e82179c9e7cbde787b54d541bad3b15f2e8fed92293fa25a',
);

Uint8List _decodeHex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// TTEncrypt：tt-data 信封（74 63 05 10 00 00 前缀）。
Uint8List ttEncrypt(List<int> input) {
  final prefixHash = _sha512(_ttEncryptPrefix);
  final keyIV = _sha512([...prefixHash, ..._ttEncryptConstant]);
  final digest = _sha512(input);
  final plain = BytesBuilder();
  plain.add(digest);
  plain.add(input);
  final padding = 16 - (plain.length % 16);
  for (var i = 0; i < padding; i++) {
    plain.addByte(padding);
  }
  final encrypted = _aesCbcEncryptPkcs7Done(plain.toBytes(), keyIV);
  final out = BytesBuilder();
  out.add([0x74, 0x63, 0x05, 0x10, 0x00, 0x00]);
  out.add(_ttEncryptPrefix);
  out.add(encrypted);
  return out.toBytes();
}

Uint8List _sha512(List<int> input) =>
    Uint8List.fromList(crypto.sha512.convert(input).bytes);

/// keyIV 前 16 字节为 AES key，后 16 为 IV；PKCS7 已由调用方填充。
Uint8List _aesCbcEncryptPkcs7Done(List<int> padded, Uint8List keyIV) {
  return aesCbcEncryptBlocks(padded, Uint8List.sublistView(keyIV, 0, 16),
      Uint8List.sublistView(keyIV, 16, 32));
}

/// AES-128-CBC 加密整块缓冲（pointycastle）。
Uint8List aesCbcEncryptBlocks(List<int> padded, List<int> key, List<int> iv) {
  final cipher = CBCBlockCipher(AESEngine());
  cipher.init(
    true,
    ParametersWithIV(KeyParameter(Uint8List.fromList(key)), Uint8List.fromList(iv)),
  );
  final out = Uint8List(padded.length);
  final src = Uint8List.fromList(padded);
  var offset = 0;
  while (offset < src.length) {
    offset += cipher.processBlock(src, offset, out, offset);
  }
  return out;
}

/// 请求体：gzip(ss_app_log 信封) 再包 tt-data（register.go）。
/// gzip 头手工写入：MTIME=now、OS=255，字节与 Go DefaultCompression 一致。
Uint8List buildRegisterBody(HongguoRegisterIdentity identity, DateTime generatedAt) {
  final plain = buildBootstrapPlaintext(identity, generatedAt);
  final gz = gzipWrap(plain, generatedAt);
  return ttEncrypt(gz);
}

/// gzip 包裹：10 字节头 + raw deflate + CRC32/ISIZE 尾。
Uint8List gzipWrap(List<int> data, DateTime mtime) {
  final header = BytesBuilder();
  header.add([0x1f, 0x8b, 0x08, 0x00]); // magic, CM=deflate, FLG=0
  final secs = mtime.toUtc().millisecondsSinceEpoch ~/ 1000;
  header.add([
    secs & 0xFF,
    (secs >> 8) & 0xFF,
    (secs >> 16) & 0xFF,
    (secs >> 24) & 0xFF,
  ]);
  header.add([0x00, 0xFF]); // XFL=0, OS=unknown
  final deflated = rawDeflate(data);
  final out = BytesBuilder();
  out.add(header.toBytes());
  out.add(deflated);
  out.add(_le32bytes(crc32(data)));
  out.add(_le32bytes(data.length & 0xFFFFFFFF));
  return out.toBytes();
}

Uint8List _le32bytes(int v) => Uint8List.fromList([
      v & 0xFF,
      (v >> 8) & 0xFF,
      (v >> 16) & 0xFF,
      (v >> 24) & 0xFF,
    ]);

/// CRC32（IEEE 802.3，zlib 同款）。
int crc32(List<int> data) {
  var crc = 0xFFFFFFFF;
  for (final b in data) {
    crc ^= b;
    for (var i = 0; i < 8; i++) {
      final mask = -(crc & 1);
      crc = (crc >>> 1) ^ (0xEDB88320 & mask);
    }
  }
  return ~crc & 0xFFFFFFFF;
}

/// 注册信封明文：{"magic_tag":"ss_app_log","header":{...},"_gen_time":millis}
/// header 键序固定（线上客户端顺序）。
Uint8List buildBootstrapPlaintext(
  HongguoRegisterIdentity identity,
  DateTime generatedAt,
) {
  final d = identity.device;
  final header = <String, Object?>{
    'display_name': '红果免费短剧',
    'update_version_code': 73932,
    'manifest_version_code': 73932,
    'app_version_minor': hongguoVersionName,
    'aid': 8662,
    'channel': d.channel,
    'package': hongguoPackage,
    'app_version': hongguoVersionName,
    'version_code': 73932,
    'os': 'Android',
    'os_version': d.osVersion,
    'os_api': d.osApi,
    'device_model': d.model,
    'device_brand': d.brand,
    'device_manufacturer': d.brand,
    'cpu_abi': 'arm64-v8a',
    'language': 'zh',
    'timezone': 8,
    'access': 'wifi',
    'region': 'CN',
    'tz_name': 'Asia/Shanghai',
    'tz_offset': 28800,
    'cdid': identity.cdId,
    'openudid': identity.openUdId,
    'clientudid': identity.clientUdId,
    'ipv6_list': <Object?>[],
    'sim_serial_number': <Object?>[],
    'oaid': buildBootstrapOAID(identity.oaId, generatedAt.subtract(const Duration(milliseconds: 200))),
    'oaid_may_support': true,
    'req_id': identity.reqId,
    'device_platform': hongguoDevicePlatform,
    'guest_mode': 0,
    'is_system_app': 0,
    'sdk_flavor': 'china',
    'device_id': '0',
    'install_id': '0',
  };
  const order = <String>[
    'display_name', 'update_version_code', 'manifest_version_code',
    'app_version_minor', 'aid', 'channel', 'package', 'app_version',
    'version_code', 'os', 'os_version', 'os_api', 'device_model',
    'device_brand', 'device_manufacturer', 'cpu_abi', 'language',
    'timezone', 'access', 'region', 'tz_name', 'tz_offset', 'cdid',
    'openudid', 'clientudid', 'ipv6_list', 'sim_serial_number', 'oaid',
    'oaid_may_support', 'req_id', 'device_platform', 'guest_mode',
    'is_system_app', 'sdk_flavor', 'device_id', 'install_id',
  ];
  final sb = StringBuffer();
  sb.write('{"magic_tag":"ss_app_log","header":{');
  var first = true;
  for (final key in order) {
    if (!header.containsKey(key)) continue;
    if (!first) sb.write(',');
    first = false;
    sb.write('${jsonEncode(key)}:${jsonEncode(header[key])}');
  }
  sb.write('},"_gen_time":');
  sb.write(generatedAt.millisecondsSinceEpoch);
  sb.write('}');
  return utf8.encode(sb.toString());
}

/// OAID 字段（对象值）。
Map<String, Object?> buildBootstrapOAID(String id, DateTime issuedAt) {
  return {
    'req_id': id,
    'hw_id_version_code': '0',
    'take_ms': '6',
    'is_track_limited': 'false',
    'query_times': '1',
    'id': id,
    'time': '${issuedAt.millisecondsSinceEpoch}',
  };
}

/// 请求体的可移植 X-SS-STUB：大写 MD5 十六进制。
String contentMD5(List<int> body) =>
    hexEncode(Uint8List.fromList(crypto.md5.convert(body).bytes)).toUpperCase();

/// raw deflate（无 zlib/gzip 包裹）。
Uint8List rawDeflate(List<int> data) =>
    Uint8List.fromList(ZLibCodec(raw: true).encode(data));
