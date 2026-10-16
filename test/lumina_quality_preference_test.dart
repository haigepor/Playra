import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/lumina/lumina_playback_provider.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/sdk_playback_coordinator.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';

void main() {
  const episode = SdkEpisode(
    number: 1,
    name: '第1集',
    code: 'mp4',
    reference: '第1集',
  );
  const lines = [SdkLine('mp4', '线路3')];

  LuminaPlaybackProvider provider(List<String> names, List<String> calls) =>
      LuminaPlaybackProvider(
        LuminaService(
          request: (op, payload, cancel) async {
            calls.add(op);
            if (op == 'detail') {
              return {
                'data': {
                  'video': {'id': '42', 'title': '作品'},
                  'parts': [
                    {
                      'play': 'mp4',
                      'name': '线路3',
                      'episodes': [
                        {'part': '第1集'},
                      ],
                    },
                  ],
                },
              };
            }
            final medias = [
              for (var i = 0; i < names.length; i++)
                {
                  'url': 'https://media.example/$i.mp4',
                  'name': names[i],
                  'format': 'mp4',
                  'headers': {
                    'User-Agent': '',
                    'Referer': 'https://media.example/',
                  },
                },
            ];
            return {
              'data': {
                'status': 'ready',
                'media': medias.first,
                'medias': medias,
              },
            };
          },
        ),
      );

  test(
    'Lumina prepares 4K from an unordered resolver list and retains exact headers',
    () async {
      final calls = <String>[];
      final sdk = provider(['1080P 高清', '4K 超清'], calls);
      final coordinator = SdkPlaybackCoordinator('42', sdk);
      addTearDown(coordinator.dispose);
      addTearDown(sdk.service.dispose);
      final result = await coordinator.preparePlayback(
        episode,
        lines,
        cancel: CancelToken(),
        onAttempt: (_, _, _) {},
      );
      expect(result.status, 'prepared');
      expect(result.quality?.height, 2160);
      expect(result.prepared?.media['url'], 'https://media.example/1.mp4');
      expect(result.prepared?.media['headers'], {
        'User-Agent': '',
        'Referer': 'https://media.example/',
      });
      expect(
        calls.where((c) => c == 'play'),
        hasLength(1),
        reason: '画质探测与预解析复用同次结果',
      );
    },
  );

  test('Lumina prefers 4K then 1080p before other resolutions', () async {
    final calls = <String>[];
    final sdk = provider(['8K 超清', '1440P', '1080P 高清'], calls);
    final coordinator = SdkPlaybackCoordinator('42', sdk);
    addTearDown(coordinator.dispose);
    addTearDown(sdk.service.dispose);
    final result = await coordinator.preparePlayback(
      episode,
      lines,
      cancel: CancelToken(),
      onAttempt: (_, _, _) {},
    );
    expect(result.quality?.height, 1080);
    expect(result.prepared?.media['url'], 'https://media.example/2.mp4');
  });

  test('failed 4K opens 1080p on the same manually locked line', () async {
    final calls = <String>[], opened = <String>[];
    final sdk = provider(['1080P 高清', '4K 超清'], calls);
    final coordinator = SdkPlaybackCoordinator('42', sdk);
    addTearDown(coordinator.dispose);
    addTearDown(sdk.service.dispose);
    final result = await coordinator.playAutomatic(
      episode,
      lines,
      manual: true,
      cancel: CancelToken(),
      onAttempt: (_, _, _) {},
      open: (_, media, _) async {
        opened.add(media['url'] as String);
        return opened.length > 1;
      },
    );
    expect(result.status, 'ready');
    expect(opened, [
      'https://media.example/1.mp4',
      'https://media.example/0.mp4',
    ]);
  });

  test('legacy single URL stays unknown and remains playable', () async {
    final calls = <String>[];
    final sdk = provider(['mp4'], calls);
    addTearDown(sdk.service.dispose);
    final result = await sdk.playEpisode('42', 'mp4', episode);
    expect(result['status'], 'ready');
    expect(
      (await sdk.qualitiesForEpisode('42', 'mp4', episode)).single.height,
      isNull,
    );
  });

  test(
    'consumed resolution materials are fetched again for expired-link recovery',
    () async {
      final calls = <String>[];
      final sdk = provider(['1080P 高清', '4K 超清'], calls);
      addTearDown(sdk.service.dispose);
      await sdk.qualitiesForEpisode('42', 'mp4', episode);
      await sdk.playEpisode('42', 'mp4', episode, quality: '2160p');
      expect(calls.where((op) => op == 'play'), hasLength(1));
      await sdk.playEpisode('42', 'mp4', episode, quality: '2160p');
      expect(
        calls.where((op) => op == 'play'),
        hasLength(2),
        reason: '403重取不能复用已经消费的直链',
      );
    },
  );

  test(
    'a missing advertised quality is unavailable instead of mislabeling another link',
    () async {
      final calls = <String>[];
      final sdk = provider(['1080P 高清'], calls);
      addTearDown(sdk.service.dispose);
      final result = await sdk.playEpisode(
        '42',
        'mp4',
        episode,
        quality: '2160p',
      );
      expect(result['status'], 'unavailable');
      expect(result['error'], 'QUALITY_UNAVAILABLE');
    },
  );

  test(
    'cancellation never consumes prepared materials or returns a stale URL',
    () async {
      final calls = <String>[];
      final sdk = provider(['1080P 高清', '4K 超清'], calls);
      addTearDown(sdk.service.dispose);
      await sdk.qualitiesForEpisode('42', 'mp4', episode);
      final cancel = CancelToken()..cancel();
      await expectLater(
        sdk.playEpisode('42', 'mp4', episode, cancel: cancel),
        throwsA(isA<Exception>()),
      );
      expect(calls.where((op) => op == 'play'), hasLength(1));
    },
  );
}
