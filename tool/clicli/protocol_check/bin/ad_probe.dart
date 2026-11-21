// Raw ad-gate probe: prints every step's response so cooldowns / error codes
// are visible instead of being collapsed into a typed exception.
//
//   cd tool/clicli/protocol_check && dart run bin/ad_probe.dart
import 'dart:convert';
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_api.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_client.dart';

Future<void> main() async {
  final client = CliCliClient();
  final api = CliCliApi(client);
  const slotCode = 'player_pre_roll';

  Future<Map<String, dynamic>?> step(
    String name,
    Future<Map<String, dynamic>> Function() run,
  ) async {
    final watch = Stopwatch()..start();
    try {
      final data = await run();
      stdout.writeln('PASS ${name.padRight(12)} ${watch.elapsedMilliseconds}ms');
      stdout.writeln('     ${jsonEncode(data)}');
      return data;
    } catch (error) {
      stdout.writeln('FAIL ${name.padRight(12)} ${watch.elapsedMilliseconds}ms $error');
      return null;
    }
  }

  await step('handshake', () => api.homeRecommend(pageSize: 1));

  final slots = await step('getSlots', () => api.adSlots());
  var placementId = '';
  final list = slots?['slots'];
  if (list is List) {
    for (final slot in list) {
      if (slot is Map && slot['slotCode'] == slotCode) {
        placementId = '${slot['placementId'] ?? slot['slotId'] ?? ''}';
        break;
      }
    }
  }

  final config = await step(
    'getConfig',
    () => api.adConfig(slotCode: slotCode, placementId: placementId),
  );
  final nonce = '${config?['nonce'] ?? ''}';

  final sessionId = api.newSessionId();
  final signatureData = await step(
    'getSignature',
    () => api.adSignature(
      adSessionId: sessionId,
      slotCode: slotCode,
      slotId: placementId,
    ),
  );
  final signature = '${signatureData?['signature'] ?? ''}';
  if (signature.isEmpty) {
    stdout.writeln('NO SIGNATURE (denyReason=${signatureData?['denyReason']}); '
        'trying direct claim');
  } else {
    for (final event in <String>['load', 'start', 'complete']) {
      final result = await step(
        'event:$event',
        () => api.reportAdEvent(
          clientTs: api.nowMs,
          duration: event == 'complete' ? 15 : 0,
          eventType: event,
          nonce: nonce,
          signature: signature,
          slotCode: slotCode,
        ),
      );
      if (result == null) break;
    }
  }

  final claim = await step(
    'claimReward',
    () => api.claimReward(nonce: nonce, slotCode: slotCode),
  );
  final adToken = '${claim?['adToken'] ?? ''}';
  stdout.writeln('adToken=${adToken.isEmpty ? '-' : '${adToken.length} chars'}');

  final qualities = await step(
    'qualities',
    () => api.qualities(
      videoId: '319731354307588097',
      code: 'mao',
      episode: 1,
    ),
  );
  final exchangeToken = '${qualities?['exchangeToken'] ?? ''}';
  if (exchangeToken.isNotEmpty) {
    await step(
      'exchange',
      () => api.exchange(
        videoId: '319731354307588097',
        code: 'mao',
        episode: 1,
        quality: '720p',
        exchangeToken: exchangeToken,
        adToken: adToken,
      ),
    );
  }
  client.close();
}
