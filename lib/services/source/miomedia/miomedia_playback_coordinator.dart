import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'miomedia_service.dart';
import '../source_models.dart';

class MioPlaybackOutcome {
  const MioPlaybackOutcome(this.status, {this.episode, this.errorCode});
  final String status;
  final MioEpisode? episode;
  final String? errorCode;
}

/// 仅编排来源调用；凭证和身份策略仍由 SDK 负责。
class MioPlaybackCoordinator {
  MioPlaybackCoordinator(
    this.videoId,
    this.service, {
    this.singleMovie = false,
  });
  final String videoId;
  final MioMediaService service;
  final bool singleMovie;
  final _cache = <String, ({DateTime at, List<MioEpisode> items})>{};
  final _pending = <String, Future<List<MioEpisode>>>{};
  final _lifetime = CancelToken();
  bool _disposed = false;
  static final _timings = <String, List<double>>{};
  static final _lastSuccess = <String, bool>{};

  String _key(MioLine line) =>
      '${kIsWeb ? 'web' : defaultTargetPlatform.name}:${line.code}';
  double? _score(MioLine line) {
    final values = _timings[_key(line)];
    return values == null
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  List<MioLine> ranked(List<MioLine> lines) {
    final result = List<MioLine>.of(lines);
    result.sort((a, b) {
      final sa = _score(a), sb = _score(b);
      if (sa == null && sb == null) {
        return lines.indexOf(a).compareTo(lines.indexOf(b));
      }
      // 已验证可起播的线路优先；未知线路其次，最近失败的线路最后。
      int tier(MioLine line, double? score) => score == null
          ? 1
          : _lastSuccess[_key(line)] == true
          ? 0
          : 2;
      final confidence = tier(a, sa).compareTo(tier(b, sb));
      if (confidence != 0) return confidence;
      final order = (sa ?? 0).compareTo(sb ?? 0);
      return order != 0 ? order : lines.indexOf(a).compareTo(lines.indexOf(b));
    });
    return result;
  }

  void _record(MioLine line, double milliseconds, {bool success = false}) {
    final key = _key(line);
    final samples = _timings.putIfAbsent(key, () => []);
    samples.add(milliseconds);
    _lastSuccess[key] = success;
    if (samples.length > 8) samples.removeAt(0);
    if (_timings.length > 64) {
      final expired = _timings.keys.first;
      _timings.remove(expired);
      _lastSuccess.remove(expired);
    }
  }

  Future<List<MioEpisode>> episodes(MioLine line, {bool refresh = false}) {
    if (_disposed) return Future.error(StateError('Playback session disposed'));
    if (refresh) _cache.remove(line.code);
    final cached = _cache[line.code];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return Future.value(cached.items);
    }
    return _pending.putIfAbsent(line.code, () => _fetchEpisodes(line));
  }

  Future<List<MioEpisode>> _fetchEpisodes(MioLine line) async {
    try {
      final items = List<MioEpisode>.unmodifiable(
        await service.episodes(videoId, line.code, cancel: _lifetime),
      );
      if (!_disposed) _cache[line.code] = (at: DateTime.now(), items: items);
      return items;
    } finally {
      _pending.remove(line.code);
    }
  }

  static MioEpisode? match(
    MioEpisode original,
    List<MioEpisode> candidates, {
    bool singleMovie = false,
  }) {
    // 同作品的单集电影用清晰度/版本作为集名；必须由电影元数据和双侧单条目录共同确认。
    if (singleMovie && candidates.length == 1) return candidates.single;
    // 特辑/日期名只能唯一完整匹配，普通集名才允许规范化数字。
    final exact = candidates
        .where((e) => e.label.trim() == original.label.trim())
        .toList();
    if (exact.length == 1) return exact.single;
    if (exact.isNotEmpty) return null;
    int? ordinary(String value) {
      final match = RegExp(
        r'^(?:第\s*)?(\d+)(?:\s*集)?$',
      ).firstMatch(value.trim());
      return match == null ? null : int.tryParse(match[1]!);
    }

    final number = ordinary(original.label);
    if (number == null) return null;
    final matches = candidates
        .where((e) => ordinary(e.label) == number)
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  Future<MioPlaybackOutcome> play(
    MioEpisode requested,
    List<MioLine> lines, {
    required CancelToken cancel,
    required FutureOr<void> Function(MioLine, MioEpisode) onAttempt,
    required Future<bool?> Function(MioEpisode, Map<dynamic, dynamic>) open,
  }) async {
    bool cancelled() => _disposed || cancel.isCancelled;
    final manual = lines.where((e) => e.code == requested.code).firstOrNull;
    if (manual == null) return const MioPlaybackOutcome('unavailable');
    final candidates = [
      manual,
      ...ranked(lines).where((e) => e.code != manual.code),
    ];
    var verifiedMovie = false;
    if (singleMovie) {
      try {
        final original = await episodes(manual);
        verifiedMovie =
            original.length == 1 && original.single.number == requested.number;
      } catch (_) {
        /* 无目录证据时保留严格匹配。 */
      }
    }
    var attempts = 0;
    var failureCode = 'PLAYBACK_UNAVAILABLE';
    for (final line in candidates) {
      if (cancelled()) return const MioPlaybackOutcome('cancelled');
      if (attempts == 3) break;
      MioEpisode? episode = requested;
      final clock = Stopwatch()..start();
      try {
        if (line.code != requested.code) {
          episode = match(
            requested,
            await episodes(line),
            singleMovie: verifiedMovie,
          );
          if (cancelled()) return const MioPlaybackOutcome('cancelled');
          if (episode == null) continue;
        }
        attempts++;
        await onAttempt(line, episode);
        if (cancelled()) return const MioPlaybackOutcome('cancelled');
        final result = await service.play(
          videoId,
          line.code,
          episode.number,
          cancel: cancel,
        );
        if (cancelled()) return const MioPlaybackOutcome('cancelled');
        if (result['status'] == 'ad_required') {
          return const MioPlaybackOutcome('ad_required');
        }
        if (result['status'] != 'ready') {
          failureCode =
              const {
                'CLIENT_PARSE_INVALID_RESPONSE',
                'CLIENT_PARSE_NETWORK',
                'CLIENT_PARSE_REJECTED',
                'QUALITY_UNAVAILABLE',
                'EXCHANGE_FAILED',
                'EMPTY_SOURCE',
                'MISSING_EXCHANGE_TOKEN',
                'UNKNOWN_PLAYBACK_RESPONSE',
              }.contains(result['error'])
              ? result['error'] as String
              : 'PLAYBACK_UNAVAILABLE';
          _record(line, 30000);
          continue;
        }
        final selection = result['selection'], media = result['media'];
        if (selection is! Map ||
            selection['videoId'] != videoId ||
            selection['code'] != line.code ||
            selection['episodeNum'] != episode.number) {
          return const MioPlaybackOutcome('identity_mismatch');
        }
        final uri = media is Map && media['url'] is String
            ? Uri.tryParse(media['url'])
            : null;
        if (uri == null ||
            !const {'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          return const MioPlaybackOutcome('invalid_media');
        }
        final started = await open(episode, media as Map);
        if (cancelled()) return const MioPlaybackOutcome('cancelled');
        if (started == null) {
          return MioPlaybackOutcome('interaction_required', episode: episode);
        }
        if (started) {
          _record(line, clock.elapsedMilliseconds.toDouble(), success: true);
          return MioPlaybackOutcome('ready', episode: episode);
        }
        _record(line, 30000);
        failureCode = 'MEDIA_LOAD_FAILED';
      } catch (error) {
        if (cancelled()) return const MioPlaybackOutcome('cancelled');
        failureCode = error is SourceException
            ? error.code
            : error is TimeoutException
            ? 'TIMEOUT'
            : 'SOURCE_ERROR';
        _record(line, 30000);
      }
    }
    return MioPlaybackOutcome('unavailable', errorCode: failureCode);
  }

  void dispose() {
    _disposed = true;
    _lifetime.cancel('Playback session disposed');
    _cache.clear();
  }
}
