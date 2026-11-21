// Player chain timing probe: breaks the resolve chain into its network
// phases, then measures the current (sequential) layout against a parallel
// one so the optimization is backed by real numbers.
//
//   cd tool/clicli/protocol_check && dart run bin/player_chain_probe.dart
import 'dart:io';

// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_api.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_client.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_config.dart';
// ignore: avoid_relative_lib_imports
import '../../../../lib/features/sources/clicli/clicli_models.dart';

class _Timing {
  int total = 0;
  int samples = 0;

  void add(int ms) {
    total += ms;
    samples++;
  }

  double get avg => samples == 0 ? 0 : total / samples;
}

Future<T> _measure<T>(_Timing timing, Future<T> Function() body) async {
  final watch = Stopwatch()..start();
  final value = await body();
  timing.add(watch.elapsedMilliseconds);
  return value;
}

String _str(Object? value) =>
    value is String ? value : (value?.toString() ?? '');

Future<String> _adToken(CliCliApi api, String placementId,
    {required bool skipSignature}) async {
  const slotCode = CliCliConfig.playerPreRollSlot;
  final config = await api.adConfig(slotCode: slotCode, placementId: placementId);
  final nonce = _str(config['nonce']);
  if (!skipSignature) {
    await api.adSignature(
      adSessionId: api.newSessionId(),
      slotCode: slotCode,
      slotId: placementId,
    );
  }
  final claim = await api.claimReward(nonce: nonce, slotCode: slotCode);
  return _str(claim['adToken']);
}

Future<void> main() async {
  final client = CliCliClient();
  final api = CliCliApi(client);

  final handshake = Stopwatch()..start();
  final home = await api.modules(page: 1);
  final feed = homeFeedFromModules(home);
  final first = feed.sections.first.items.first;
  stdout.writeln('session warm (modules): ${handshake.elapsedMilliseconds}ms');

  final episodes = await api.episodes(first.key.mediaId);
  final videos = await api.videoDetail(first.key.mediaId);
  final video = videos['video'];
  final detail = mediaDetailFromVideo(
    Map<String, dynamic>.from(video as Map),
    episodes: episodes,
  );
  final road = detail.defaultRoad!;
  final episode = road.episodes.first.number;
  stdout.writeln(
    'target: ${detail.title} id=${detail.key.mediaId} road=${road.code} ep=$episode',
  );

  const slotCode = CliCliConfig.playerPreRollSlot;
  final slotsTiming = _Timing();
  final slots = await _measure(
    slotsTiming,
    () => api.adSlots(),
  );
  var placementId = '';
  final slotList = slots['slots'];
  if (slotList is List) {
    for (final slot in slotList) {
      if (slot is! Map) continue;
      if (_str(slot['slotCode']) != slotCode) continue;
      placementId = _str(slot['placementId']).isEmpty
          ? _str(slot['slotId'])
          : _str(slot['placementId']);
      break;
    }
  }
  stdout.writeln('adSlots cold: ${slotsTiming.avg.toStringAsFixed(0)}ms '
      'placement=${placementId.isEmpty ? "<empty>" : placementId}');

  // ---- phase breakdown, current sequential layout (3 rounds) ----
  final qualityTiming = _Timing();
  final configTiming = _Timing();
  final signatureTiming = _Timing();
  final claimTiming = _Timing();
  final exchangeTiming = _Timing();
  final sequentialTiming = _Timing();
  var devicePass = false;

  for (var round = 0; round < 3; round++) {
    final total = Stopwatch()..start();
    final qualities = await _measure(
      qualityTiming,
      () => api.qualities(
        videoId: detail.key.mediaId,
        code: road.code,
        episode: episode,
      ),
    );
    final parsed = qualitiesFromData(qualities);
    final selected = parsed.firstWhere((q) => !q.vipOnly, orElse: () => parsed.first);
    final exchangeToken = _str(qualities['exchangeToken']);

    final config = await _measure(
      configTiming,
      () => api.adConfig(slotCode: slotCode, placementId: placementId),
    );
    final nonce = _str(config['nonce']);
    final signature = await _measure(
      signatureTiming,
      () => api.adSignature(
        adSessionId: api.newSessionId(),
        slotCode: slotCode,
        slotId: placementId,
      ),
    );
    devicePass = signature['shouldShow'] == false;
    final claim = await _measure(
      claimTiming,
      () => api.claimReward(nonce: nonce, slotCode: slotCode),
    );
    final adToken = _str(claim['adToken']);
    if (adToken.isEmpty) {
      stdout.writeln('round $round: claim returned no adToken (skip exchange)');
      continue;
    }
    final exchanged = await _measure(
      exchangeTiming,
      () => api.exchange(
        videoId: detail.key.mediaId,
        code: road.code,
        episode: episode,
        quality: selected.id,
        exchangeToken: exchangeToken,
        adToken: adToken,
      ),
    );
    final source = playbackSourceFromExchange(exchanged);
    sequentialTiming.add(total.elapsedMilliseconds);
    stdout.writeln(
      'round $round sequential: total=${total.elapsedMilliseconds}ms '
      'qualities=${qualityTiming.samples} url=${source.url.isEmpty ? "EMPTY" : "ok"} '
      'shouldShow=$devicePass',
    );
  }

  stdout.writeln(
    'phases avg: qualities=${qualityTiming.avg.toStringAsFixed(0)}ms '
    'adConfig=${configTiming.avg.toStringAsFixed(0)}ms '
    'adSignature=${signatureTiming.avg.toStringAsFixed(0)}ms '
    'claim=${claimTiming.avg.toStringAsFixed(0)}ms '
    'exchange=${exchangeTiming.avg.toStringAsFixed(0)}ms',
  );
  stdout.writeln('sequential avg: ${sequentialTiming.avg.toStringAsFixed(0)}ms');

  // ---- parallel layout: qualities || ad gate, then exchange ----
  final parallelTiming = _Timing();
  for (var round = 0; round < 3; round++) {
    final total = Stopwatch()..start();
    final qualitiesFuture = api.qualities(
      videoId: detail.key.mediaId,
      code: road.code,
      episode: episode,
    );
    final adFuture = _adToken(api, placementId, skipSignature: false);
    final qualities = await qualitiesFuture;
    final adToken = await adFuture;
    final parsed = qualitiesFromData(qualities);
    final selected = parsed.firstWhere((q) => !q.vipOnly, orElse: () => parsed.first);
    final exchanged = await api.exchange(
      videoId: detail.key.mediaId,
      code: road.code,
      episode: episode,
      quality: selected.id,
      exchangeToken: _str(qualities['exchangeToken']),
      adToken: adToken,
    );
    final source = playbackSourceFromExchange(exchanged);
    parallelTiming.add(total.elapsedMilliseconds);
    stdout.writeln(
      'round $round parallel: total=${total.elapsedMilliseconds}ms '
      'url=${source.url.isEmpty ? "EMPTY" : "ok"}',
    );
  }
  stdout.writeln('parallel avg: ${parallelTiming.avg.toStringAsFixed(0)}ms');

  // ---- device_pass shortcut: claim directly without adSignature ----
  if (devicePass) {
    final shortcut = _Timing();
    for (var round = 0; round < 2; round++) {
      final token = await _measure(
        shortcut,
        () => _adToken(api, placementId, skipSignature: true),
      );
      stdout.writeln(
        'device_pass shortcut round $round: ${shortcut.avg.toStringAsFixed(0)}ms '
        'token=${token.isEmpty ? "EMPTY" : "ok"}',
      );
    }
  }

  client.close();
}
