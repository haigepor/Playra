/// Thin typed wrappers over the CliCli business endpoints used by the source.
library;

import 'dart:math';

import 'clicli_client.dart';
import 'clicli_config.dart';

class CliCliApi {
  CliCliApi(this._client);

  final CliCliClient _client;

  Future<Map<String, dynamic>> homeRecommend({
    int page = 1,
    int pageSize = 20,
  }) {
    return _client.callData(CliCliConfig.pathHome, <String, dynamic>{
      'categoryId': '',
      'tags': <String>[],
      'pageIndex': page,
      'pageSize': pageSize,
      'videoId': '',
    });
  }

  Future<Map<String, dynamic>> modules({
    String categoryId = '',
    int page = 1,
    int pageSize = 20,
  }) {
    return _client.callData(CliCliConfig.pathModules, <String, dynamic>{
      'categoryId': categoryId,
      'pageIndex': page,
      'pageSize': pageSize,
    });
  }

  /// All active categories, including child types, merged across pages.
  Future<Map<String, dynamic>> allTypes() async {
    const pageSize = 50;
    final first = await _client.callData(CliCliConfig.pathTypes, <String, dynamic>{
      'parentId': '',
      'parentCode': '',
      'withChannel': '1',
      'pageIndex': 1,
      'pageSize': pageSize,
    });
    final types = <dynamic>[...?(first['types'] as List?)];
    final pageInfo = first['pageinfo'];
    final pages = pageInfo is Map ? _asInt(pageInfo['pages']) ?? 1 : 1;
    for (var page = 2; page <= pages; page++) {
      final next = await _client.callData(CliCliConfig.pathTypes, <String, dynamic>{
        'parentId': '',
        'parentCode': '',
        'withChannel': '1',
        'pageIndex': page,
        'pageSize': pageSize,
      });
      types.addAll(next['types'] as List? ?? const []);
    }
    return <String, dynamic>{'types': types, 'pageinfo': pageInfo};
  }

  Future<Map<String, dynamic>> categoryVideos({
    required String categoryId,
    int page = 1,
    int pageSize = 20,
    String sort = '',
    String billing = '',
  }) {
    return _client.callData(CliCliConfig.pathCategoryVideos, <String, dynamic>{
      'categoryId': categoryId,
      'pageIndex': page,
      'pageSize': pageSize,
      'sort': sort,
      'filters': <dynamic>[],
      'billing': billing,
    });
  }

  Future<Map<String, dynamic>> search(
    String keyword, {
    int page = 1,
    int pageSize = 20,
  }) {
    return _client.callData(CliCliConfig.pathSearch, <String, dynamic>{
      'keyword': keyword,
      'pageIndex': page,
      'pageSize': pageSize,
      'categoryId': '',
      'tags': '',
    });
  }

  Future<Map<String, dynamic>> videoDetail(String videoId) {
    return _client.callData(CliCliConfig.pathDetail, <String, dynamic>{
      'videoId': videoId,
    });
  }

  Future<List<Map<String, dynamic>>> episodes(String videoId) async {
    final data = await _client.callData(CliCliConfig.pathEpisodes, <String, dynamic>{
      'videoId': videoId,
    });
    final episodes = data['episodes'];
    if (episodes is! List) return const <Map<String, dynamic>>[];
    return <Map<String, dynamic>>[
      for (final episode in episodes)
        if (episode is Map) Map<String, dynamic>.from(episode),
    ];
  }

  Future<Map<String, dynamic>> qualities({
    required String videoId,
    required String code,
    required int episode,
  }) {
    return _client.callData(CliCliConfig.pathQualities, <String, dynamic>{
      'videoId': videoId,
      'code': code,
      'episodeNum': episode,
      'caps': CliCliConfig.caps,
    });
  }

  Future<Map<String, dynamic>> adSlots() {
    return _client.callData(CliCliConfig.pathAdSlots, const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> banners({String categoryId = ''}) {
    return _client.callData(CliCliConfig.pathBanners, <String, dynamic>{
      'categoryId': categoryId,
    });
  }

  Future<Map<String, dynamic>> adConfig({
    required String slotCode,
    required String placementId,
  }) {
    return _client.callData(CliCliConfig.pathAdConfig, <String, dynamic>{
      'isVertical': false,
      'slotCode': slotCode,
      'placementId': placementId,
    });
  }

  Future<Map<String, dynamic>> adSignature({
    required String adSessionId,
    required String slotCode,
    required String slotId,
  }) {
    return _client.callData(CliCliConfig.pathAdSignature, <String, dynamic>{
      'adSessionId': adSessionId,
      'slotCode': slotCode,
      'slotId': slotId,
    });
  }

  Future<Map<String, dynamic>> reportAdEvent({
    required int clientTs,
    required int duration,
    required String eventType,
    required String nonce,
    required String signature,
    required String slotCode,
  }) {
    return _client.callData(CliCliConfig.pathAdReportEvent, <String, dynamic>{
      'clientTs': clientTs,
      'duration': duration,
      'eventType': eventType,
      'extra': '',
      'nonce': nonce,
      'signature': signature,
      'slotCode': slotCode,
    });
  }

  Future<Map<String, dynamic>> claimReward({
    required String nonce,
    required String slotCode,
  }) {
    return _client.callData(CliCliConfig.pathAdClaimReward, <String, dynamic>{
      'nonce': nonce,
      'slotCode': slotCode,
      'taskCode': '',
    });
  }

  Future<Map<String, dynamic>> exchange({
    required String videoId,
    required String code,
    required int episode,
    required String quality,
    required String exchangeToken,
    required String adToken,
  }) {
    return _client.callData(CliCliConfig.pathExchange, <String, dynamic>{
      'videoId': videoId,
      'code': code,
      'episodeNum': episode,
      'quality': quality,
      'exchangeToken': exchangeToken,
      'adToken': adToken,
    });
  }

  int get nowMs => _client.nowMs;

  String newSessionId() {
    // 32 hex chars, same shape as the app's ad session id.
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

final Random _random = Random.secure();

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
