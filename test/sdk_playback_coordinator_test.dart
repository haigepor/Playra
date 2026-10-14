import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/source/sdk_playback_provider.dart';
import 'package:kazumi/services/source/sdk_playback_coordinator.dart';

class TestSdk extends SdkPlaybackProvider {
  TestSdk({this.provider = 'other_sdk'});
  final String provider;
  @override
  String get id => provider;
  @override
  String get name => provider;
  @override
  bool get supportsQualities => true;
  final heights = <String, List<SdkQuality>>{};
  final played = <String>[];
  final failed = <String>{};
  final held = <String, Completer<void>>{};
  final probes = <String>[];
  int active = 0, peak = 0;
  Completer<void>? exchangeGate;
  @override
  Future<SdkVideo> detail(String id, {CancelToken? cancel}) async =>
      SdkVideoData(
        id: id,
        title: '外部 SDK 作品',
        lines: [for (final code in heights.keys) SdkLine(code, code)],
      );
  @override
  Future<List<SdkEpisode>> episodes(
    String id,
    String code, {
    CancelToken? cancel,
  }) async => [
    SdkEpisode(number: code == 'first' ? 1 : 914, name: '第01集', code: code),
  ];
  @override
  Future<List<SdkQuality>> qualities(
    String id,
    String code,
    int episode, {
    CancelToken? cancel,
  }) async {
    probes.add(code);
    active++;
    if (active > peak) peak = active;
    try {
      await held[code]?.future;
      return heights[code] ?? [];
    } finally {
      active--;
    }
  }

  @override
  Future<Map<String, dynamic>> play(
    String id,
    String code,
    int episode, {
    String? quality,
    CancelToken? cancel,
  }) async {
    played.add('$code:${quality ?? "auto"}:$episode');
    await exchangeGate?.future;
    return {
      'status': failed.contains('$code:$quality') ? 'unavailable' : 'ready',
      'selection': {'videoId': id, 'code': code, 'episodeNum': episode},
      'media': {'url': 'https://example.test/video.mp4'},
    };
  }
}

const anchor = SdkEpisode(number: 1, name: '第01集', code: 'first');
List<SdkLine> lines(TestSdk sdk) => [
  for (final c in sdk.heights.keys) SdkLine(c, '蓝光$c'),
];
Future<SdkPlaybackOutcome> auto(
  SdkPlaybackCoordinator c,
  TestSdk s, {
  bool manual = false,
  CancelToken? cancel,
}) => c.playAutomatic(
  anchor,
  lines(s),
  cancel: cancel ?? CancelToken(),
  manual: manual,
  onAttempt: (_, _, _) {},
  open: (_, _, _) async => true,
);

void main() {
  test(
    'quality timeout retains the already matched playable episode',
    () async {
      final sdk = TestSdk()
        ..heights['first'] = [const SdkQuality('1080p', height: 1080)];
      sdk.held['first'] = Completer<void>();
      final c = SdkPlaybackCoordinator(
        'foreign-id',
        sdk,
        metadataBudget: const Duration(milliseconds: 15),
      );
      addTearDown(c.dispose);
      try {
        expect((await auto(c, sdk)).status, 'ready');
        expect(sdk.played, ['first:auto:1']);
      } finally {
        sdk.held['first']!.complete();
      }
    },
  );
  test(
    'overall playback budget interrupts a hung exchange without opening late media',
    () async {
      final sdk = TestSdk()
        ..heights['first'] = [const SdkQuality('1080p', height: 1080)];
      sdk.exchangeGate = Completer<void>();
      final c = SdkPlaybackCoordinator(
        'foreign-id',
        sdk,
        playbackBudget: const Duration(milliseconds: 20),
      );
      addTearDown(c.dispose);
      try {
        final result = await auto(
          c,
          sdk,
        ).timeout(const Duration(milliseconds: 120));
        expect(result.errorCode, 'ATTEMPT_BUDGET_EXHAUSTED');
        expect(result.status, 'unavailable');
      } finally {
        sdk.exchangeGate!.complete();
      }
    },
  );
  test(
    'highest declared quality wins across all lines and does not trust names or array order',
    () async {
      final sdk = TestSdk()
        ..heights.addAll({
          'first': [const SdkQuality('720p', height: 720)],
          'new_8': [
            const SdkQuality('1080p', height: 1080),
            const SdkQuality('2160p', height: 2160),
          ],
        });
      final c = SdkPlaybackCoordinator('foreign-id/abc', sdk);
      addTearDown(c.dispose);
      expect((await auto(c, sdk)).status, 'ready');
      expect(sdk.played, ['new_8:2160p:914']);
    },
  );
  test('quality probes overlap before waiting for a slow first line', () async {
    final sdk = TestSdk()
      ..heights.addAll({
        for (final c in ['first', 'second', 'third'])
          c: [const SdkQuality('1080p', height: 1080)],
      });
    sdk.held['first'] = Completer<void>();
    final c = SdkPlaybackCoordinator('foreign-id', sdk);
    addTearDown(c.dispose);
    final pending = auto(c, sdk);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sdk.probes.toSet(), {'first', 'second', 'third'});
    sdk.held['first']!.complete();
    await pending;
  });
  test(
    'failed UHD tries the same quality elsewhere before downgrading',
    () async {
      final sdk = TestSdk()
        ..heights.addAll({
          'first': [const SdkQuality('1080p', height: 1080)],
          'uhd': [const SdkQuality('2160p', height: 2160)],
        })
        ..failed.add('uhd:2160p');
      final c = SdkPlaybackCoordinator('foreign-id', sdk);
      addTearDown(c.dispose);
      expect((await auto(c, sdk)).status, 'ready');
      expect(sdk.played, ['uhd:2160p:914', 'first:1080p:1']);
    },
  );
  test('manual line never silently falls back to another SDK line', () async {
    final sdk = TestSdk()
      ..heights.addAll({
        'first': [const SdkQuality('720p', height: 720)],
        'uhd': [const SdkQuality('2160p', height: 2160)],
      })
      ..failed.add('first:720p');
    final c = SdkPlaybackCoordinator('foreign-id', sdk);
    addTearDown(c.dispose);
    expect((await auto(c, sdk, manual: true)).status, 'unavailable');
    expect(sdk.played, ['first:720p:1']);
  });
  test('cancelled comparison cannot exchange or open stale media', () async {
    final sdk = TestSdk()
      ..heights['first'] = [const SdkQuality('1080p', height: 1080)];
    sdk.held['first'] = Completer<void>();
    final c = SdkPlaybackCoordinator('foreign-id', sdk);
    addTearDown(c.dispose);
    final cancel = CancelToken();
    final pending = auto(c, sdk, cancel: cancel);
    await Future<void>.delayed(Duration.zero);
    cancel.cancel();
    sdk.held['first']!.complete();
    expect((await pending).status, 'cancelled');
    expect(sdk.played, isEmpty);
  });
  test(
    'unknown quality stays unknown instead of turning source names into 4K',
    () {
      expect(
        SdkQuality.fromJson({'quality': 'origin', 'label': '蓝光超清+'})!.height,
        isNull,
      );
      expect(
        SdkQuality.fromJson({
          'quality': 'x',
          'resolution': '3840x2160',
        })!.height,
        2160,
      );
    },
  );
}
