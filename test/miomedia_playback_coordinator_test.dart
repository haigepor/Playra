import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/miomedia/miomedia_playback_coordinator.dart';

MioEpisode episode(String code, int number, String name) => MioEpisode.fromJson(
  {'code': code, 'episodeNum': number, 'displayName': name},
);

void main() {
  test('recovery sends at most three actual playback requests', () async {
    var attempts = 0;
    final lines = List.generate(5, (i) => MioLine('limit_$i', '$i'));
    final service = MioMediaService(
      request: (op, payload, cancel) async {
        if (op == 'play') {
          attempts++;
          return {
            'data': {'status': 'unavailable'},
          };
        }
        return {
          'data': {
            'episodes': [
              {
                'code': payload['code'],
                'episodeNum': 71,
                'displayName': '第01集',
              },
            ],
          },
        };
      },
    );
    final session = MioPlaybackCoordinator('123', service);
    final result = await session.play(
      episode('limit_0', 1, '第01集'),
      lines,
      cancel: CancelToken(),
      onAttempt: (_, _) {},
      open: (_, _) async => true,
    );
    expect(result.status, 'unavailable');
    expect(attempts, 3);
    session.dispose();
    service.dispose();
  });
  test('foreign selection is rejected before opening media', () async {
    var opens = 0;
    final service = MioMediaService(
      request: (op, payload, cancel) async => {
        'data': {
          'status': 'ready',
          'selection': {'videoId': '456', 'code': 'foreign', 'episodeNum': 1},
          'media': {'url': 'https://example.test/video.mp4'},
        },
      },
    );
    final session = MioPlaybackCoordinator('123', service);
    final result = await session.play(
      episode('foreign', 1, '第01集'),
      [const MioLine('foreign', '')],
      cancel: CancelToken(),
      onAttempt: (_, _) {},
      open: (_, _) async {
        opens++;
        return true;
      },
    );
    expect(result.status, 'identity_mismatch');
    expect(opens, 0);
    session.dispose();
    service.dispose();
  });
  test(
    'matching rejects duplicate names and preserves nonconsecutive target numbers',
    () {
      final original = episode('a', 1, '第01集');
      expect(
        MioPlaybackCoordinator.match(original, [episode('b', 71, '1')])!.number,
        71,
      );
      expect(
        MioPlaybackCoordinator.match(original, [
          episode('b', 71, '1'),
          episode('b', 81, '1'),
        ]),
        isNull,
      );
      final special = episode('a', 5, '回顾特辑');
      expect(
        MioPlaybackCoordinator.match(special, [
          episode('b', 8, '回顾特辑'),
          episode('b', 9, '回顾特辑'),
        ]),
        isNull,
      );
    },
  );
  test(
    'switching away does not discard a completed shared episode request',
    () async {
      final pending = Completer<Map<String, dynamic>>();
      var count = 0;
      final service = MioMediaService(
        request: (op, payload, cancel) async {
          count++;
          return pending.future;
        },
      );
      final session = MioPlaybackCoordinator('123', service);
      final a = session.episodes(const MioLine('a', 'A'));
      final b = session.episodes(const MioLine('a', 'A'));
      pending.complete({
        'data': {
          'episodes': [
            {'code': 'a', 'episodeNum': 12, 'displayName': '第12集'},
          ],
        },
      });
      expect((await a).single.number, 12);
      expect((await b).single.number, 12);
      expect(
        (await session.episodes(const MioLine('a', 'A'))).single.number,
        12,
      );
      expect(count, 1);
      session.dispose();
      service.dispose();
    },
  );

  test(
    'failed decoding recovers the same named episode with its real target number',
    () async {
      final opened = <String>[];
      final service = MioMediaService(
        request: (op, payload, cancel) async => {
          'data': op == 'episodes'
              ? {
                  'episodes': [
                    {
                      'code': payload['code'],
                      'episodeNum': 99,
                      'displayName': '20260401回顾特辑',
                    },
                  ],
                }
              : {
                  'status': 'ready',
                  'selection': {...payload},
                  'media': {'url': 'https://example.test/video.mp4'},
                },
        },
      );
      final session = MioPlaybackCoordinator('123', service);
      final result = await session.play(
        episode('a', 12, '20260401回顾特辑'),
        [const MioLine('a', 'A'), const MioLine('b', 'B')],
        cancel: CancelToken(),
        onAttempt: (_, _) {},
        open: (ep, _) async {
          opened.add('${ep.code}:${ep.number}');
          return ep.code == 'b';
        },
      );
      expect(result.status, 'ready');
      expect(opened, ['a:12', 'b:99']);
      expect(
        session
            .ranked([
              const MioLine('a', 'A'),
              const MioLine('unknown', '未知'),
              const MioLine('b', 'B'),
            ])
            .map((e) => e.code),
        ['b', 'unknown', 'a'],
      );
      session.dispose();
      service.dispose();
    },
  );

  test('same array index is not sufficient to substitute an episode', () async {
    var opens = 0;
    final service = MioMediaService(
      request: (op, payload, cancel) async => {
        'data': op == 'episodes'
            ? {
                'episodes': [
                  {
                    'code': payload['code'],
                    'episodeNum': 12,
                    'displayName': '其他特辑',
                  },
                ],
              }
            : {'status': 'unavailable'},
      },
    );
    final session = MioPlaybackCoordinator('123', service);
    final result = await session.play(
      episode('a', 12, '回顾特辑'),
      [const MioLine('a', 'A'), const MioLine('b', 'B')],
      cancel: CancelToken(),
      onAttempt: (_, _) {},
      open: (_, _) async {
        opens++;
        return true;
      },
    );
    expect(result.status, 'unavailable');
    expect(opens, 0);
    session.dispose();
    service.dispose();
  });

  test(
    'ad_required does not rotate identity or attempt another line',
    () async {
      var calls = 0;
      final service = MioMediaService(
        request: (op, payload, cancel) async {
          calls++;
          return {
            'data': {'status': 'ad_required'},
          };
        },
      );
      final session = MioPlaybackCoordinator('123', service);
      final result = await session.play(
        episode('a', 1, '第01集'),
        [const MioLine('a', 'A'), const MioLine('b', 'B')],
        cancel: CancelToken(),
        onAttempt: (_, _) {},
        open: (_, _) async => true,
      );
      expect(result.status, 'ad_required');
      expect(calls, 1);
      session.dispose();
      service.dispose();
    },
  );

  test('cancelled selection cannot open its stale media', () async {
    final pending = Completer<Map<String, dynamic>>();
    final service = MioMediaService(
      request: (op, payload, cancel) => pending.future,
    );
    final session = MioPlaybackCoordinator('123', service);
    final cancel = CancelToken();
    var opens = 0;
    final play = session.play(
      episode('a', 1, '第01集'),
      [const MioLine('a', 'A')],
      cancel: cancel,
      onAttempt: (_, _) {},
      open: (_, _) async {
        opens++;
        return true;
      },
    );
    cancel.cancel();
    pending.complete({
      'data': {
        'status': 'ready',
        'selection': {'videoId': '123', 'code': 'a', 'episodeNum': 1},
        'media': {'url': 'https://example.test/video.mp4'},
      },
    });
    expect((await play).status, 'cancelled');
    expect(opens, 0);
    session.dispose();
    service.dispose();
  });
}
