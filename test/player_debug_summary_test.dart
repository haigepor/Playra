import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_debug_controller.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  const secret = 'private_token_123';
  test('native log text, prefix and unrecognized level are never exposed', () {
    final event = PlayerLog(
      prefix: 'https://example.test/?token=$secret',
      level: 'error Authorization: Bearer $secret',
      text: 'Referer: $secret Cookie: $secret',
    );
    final result = PlayerDebugSummary.log(event);
    expect(result, contains('其他'));
    expect(result, isNot(contains(secret)));
    expect(result, isNot(contains('Authorization')));
    expect(
      PlayerDebugSummary.log(
        const PlayerLog(prefix: '', level: 'error', text: ''),
      ),
      contains('错误'),
    );
  });

  test('playlist summary includes only numerical structure', () {
    final value = Playlist([
      Media(
        'https://example.test/private?token=$secret',
        httpHeaders: {'Authorization': 'Bearer $secret'},
      ),
    ]);
    final summary = PlayerDebugSummary.playlist(value);
    expect(summary, '条目数：1，当前序号：1');
    expect(summary, isNot(contains(secret)));
    expect(PlayerDebugSummary.playlist(const Playlist([])), contains('当前序号：无'));
  });

  test('track and codec parameters omit untrusted string metadata', () {
    final audio = AudioTrack(
      secret,
      'Authorization $secret',
      secret,
      channelscount: 2,
      samplerate: 48000,
    );
    final video = VideoTrack(secret, secret, secret, w: 1920, h: 1080, fps: 24);
    final videoParams = VideoParams(w: 1920, h: 1080, pixelformat: secret);
    final audioParams = AudioParams(
      sampleRate: 48000,
      channelCount: 2,
      format: secret,
    );
    final summaries = [
      PlayerDebugSummary.audioTrack(audio),
      PlayerDebugSummary.videoTrack(video),
      PlayerDebugSummary.audioParams(audioParams),
      PlayerDebugSummary.videoParams(videoParams),
    ];
    for (final summary in summaries) {
      expect(summary, isNot(contains(secret)));
    }
    expect(summaries[0], contains('48000'));
    expect(summaries[1], contains('1920'));
  });

  test('long sessions keep at most 500 sanitized debug entries', () {
    final controller = PlayerDebugController();
    for (var i = 0; i < 750; i++) {
      controller.recordLog(
        PlayerLog(
          prefix: secret,
          level: i == 749 ? 'warn' : 'info',
          text: secret,
        ),
      );
    }
    expect(controller.playerLog, hasLength(500));
    expect(controller.playerLog.last, contains('警告'));
    expect(
      controller.playerLog.any((entry) => entry.contains(secret)),
      isFalse,
    );
  });
}
