import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/clicli/clicli_api.dart';
import 'package:kazumi/features/sources/clicli/clicli_client.dart';
import 'package:kazumi/features/sources/core/media_source.dart';
import 'package:kazumi/features/sources/clicli/clicli_config.dart';
import 'package:kazumi/features/sources/clicli/clicli_source.dart';

class RecordingClient extends CliCliClient {
  final calls = <(String, Map<String, dynamic>)>[];

  @override
  Future<Map<String, dynamic>> callData(
    String path,
    Map<String, dynamic> payload, {
    Duration? timeout,
  }) async {
    calls.add((path, payload));
    return {
      'videos': [],
      'pageinfo': {'pages': 1, 'pageIndex': 1},
    };
  }
}

class QualityApi extends CliCliApi {
  QualityApi(this.qualitiesResult, {this.reject4k = false})
    : super(RecordingClient());
  final List<Map<String, Object>> qualitiesResult;
  final bool reject4k;
  final requested = <String>[];

  @override
  Future<Map<String, dynamic>> qualities({
    required String videoId,
    required String code,
    required int episode,
  }) async => {'qualities': qualitiesResult, 'exchangeToken': 'exchange'};
  @override
  Future<Map<String, dynamic>> adSlots() async => {'slots': []};
  @override
  Future<Map<String, dynamic>> adConfig({
    required String slotCode,
    required String placementId,
  }) async => {'nonce': 'nonce'};
  @override
  Future<Map<String, dynamic>> adSignature({
    required String adSessionId,
    required String slotCode,
    required String slotId,
  }) async => {'shouldShow': false};
  @override
  Future<Map<String, dynamic>> claimReward({
    required String nonce,
    required String slotCode,
  }) async => {'adToken': 'ad'};
  @override
  Future<Map<String, dynamic>> exchange({
    required String videoId,
    required String code,
    required int episode,
    required String quality,
    required String exchangeToken,
    required String adToken,
  }) async {
    requested.add(quality);
    if (quality == '4k' && reject4k)
      throw const MediaSourceException(
        MediaSourceErrorKind.vipRequired,
        'vip',
        code: 4032,
      );
    return {'playUrl': 'https://example.test/$quality', 'quality': quality};
  }
}

void main() {
  for (final reject in [false, true]) {
    test(
      'automatic quality prefers 4k and falls back on VIP rejection: $reject',
      () async {
        final api = QualityApi([
          {'quality': '4k', 'isVipOnly': true},
          {'quality': '1080p'},
        ], reject4k: reject);
        final source = CliCliSource(api: api);
        final result = await source.resolvePlayback(
          mediaId: '1',
          roadCode: 'a',
          episode: 1,
        );
        expect(api.requested, reject ? ['4k', '1080p'] : ['4k']);
        expect(result.quality, reject ? '1080p' : '4k');
      },
    );
  }
  test('automatic quality falls back to available 1080p', () async {
    final api = QualityApi([
      {'quality': '1080p'},
    ]);
    final source = CliCliSource(api: api);
    final result = await source.resolvePlayback(
      mediaId: '1',
      roadCode: 'a',
      episode: 1,
    );
    expect(result.quality, '1080p');
  });
  for (final (sort, expected) in const [
    ('', ''),
    ('hot', 'hottest'),
    ('new', 'latest'),
    ('score', 'score'),
  ]) {
    test('browse sort "$sort" uses API value "$expected"', () async {
      final client = RecordingClient();
      final source = CliCliSource(client: client);
      await source.browse(categoryId: 'anime', sort: sort);
      expect(client.calls.single.$1, CliCliConfig.pathCategoryVideos);
      expect(client.calls.single.$2['sort'], expected);
      expect(client.calls.single.$2['categoryId'], 'anime');
    });
  }
}
