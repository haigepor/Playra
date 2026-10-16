import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'sdk_playback_models.dart';
import 'sdk_playback_provider.dart';
import 'source_models.dart';
import 'prepared_playback.dart';

class SdkPlaybackOutcome {
  const SdkPlaybackOutcome(
    this.status, {
    this.episode,
    this.errorCode,
    this.quality,
    this.untried = 0,
    this.prepared,
  });
  final String status;
  final SdkEpisode? episode;
  final String? errorCode;
  final SdkQuality? quality;
  final int untried;
  final PreparedPlayback? prepared;
}

/// 仅编排来源调用；凭证和身份策略仍由 SDK 负责。
class SdkPlaybackCoordinator {
  SdkPlaybackCoordinator(
    this.videoId,
    this.service, {
    this.singleMovie = false,
    this.onChanged,
    this.metadataBudget = const Duration(seconds: 10),
    this.playbackBudget = const Duration(seconds: 75),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;
  final String videoId;
  final SdkPlaybackProvider service;
  final bool singleMovie;
  final void Function()? onChanged;
  final Duration metadataBudget, playbackBudget;
  final DateTime Function() _now;
  List<SdkLineCandidate> candidates = const [];
  int _probeGeneration = 0;
  final _cache = <String, ({DateTime at, List<SdkEpisode> items})>{};
  final _pending = <String, Future<List<SdkEpisode>>>{};
  final _lifetime = CancelToken();
  bool _disposed = false;
  static final _timings = <String, List<double>>{};
  static final _lastSuccess = <String, bool>{};

  String _key(SdkLine line) =>
      '${service.id}:${kIsWeb ? 'web' : defaultTargetPlatform.name}:${line.code}';
  double? _score(SdkLine line) {
    final values = _timings[_key(line)];
    return values == null
        ? null
        : values.reduce((a, b) => a + b) / values.length;
  }

  List<SdkLine> ranked(List<SdkLine> lines) {
    final result = List<SdkLine>.of(lines);
    result.sort((a, b) {
      final sa = _score(a), sb = _score(b);
      if (sa == null && sb == null) {
        return lines.indexOf(a).compareTo(lines.indexOf(b));
      }
      // 已验证可起播的线路优先；未知线路其次，最近失败的线路最后。
      int tier(SdkLine line, double? score) => score == null
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

  void _record(SdkLine line, double milliseconds, {bool success = false}) {
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

  Future<List<SdkEpisode>> episodes(SdkLine line, {bool refresh = false}) {
    if (_disposed) return Future.error(StateError('Playback session disposed'));
    if (refresh) _cache.remove(line.code);
    final cached = _cache[line.code];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 5)) {
      return Future.value(cached.items);
    }
    return _pending.putIfAbsent(line.code, () => _fetchEpisodes(line));
  }

  Future<List<SdkEpisode>> _fetchEpisodes(SdkLine line) async {
    try {
      final items = List<SdkEpisode>.unmodifiable(
        await service.episodes(videoId, line.code, cancel: _lifetime),
      );
      if (!_disposed) _cache[line.code] = (at: DateTime.now(), items: items);
      return items;
    } finally {
      _pending.remove(line.code);
    }
  }

  static SdkEpisode? match(
    SdkEpisode original,
    List<SdkEpisode> candidates, {
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

  Future<SdkPlaybackOutcome> play(
    SdkEpisode requested,
    List<SdkLine> lines, {
    required CancelToken cancel,
    required FutureOr<void> Function(SdkLine, SdkEpisode) onAttempt,
    required Future<bool?> Function(SdkEpisode, Map<dynamic, dynamic>) open,
  }) async {
    bool cancelled() => _disposed || cancel.isCancelled;
    final manual = lines.where((e) => e.code == requested.code).firstOrNull;
    if (manual == null) return const SdkPlaybackOutcome('unavailable');
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
      if (cancelled()) return const SdkPlaybackOutcome('cancelled');
      if (attempts == 3) break;
      SdkEpisode? episode = requested;
      final clock = Stopwatch()..start();
      try {
        if (line.code != requested.code) {
          episode = match(
            requested,
            await episodes(line),
            singleMovie: verifiedMovie,
          );
          if (cancelled()) return const SdkPlaybackOutcome('cancelled');
          if (episode == null) continue;
        }
        attempts++;
        await onAttempt(line, episode);
        if (cancelled()) return const SdkPlaybackOutcome('cancelled');
        final result = await service.playEpisode(
          videoId,
          line.code,
          episode,
          cancel: cancel,
        );
        if (cancelled()) return const SdkPlaybackOutcome('cancelled');
        if (result['status'] == 'ad_required') {
          return const SdkPlaybackOutcome('ad_required');
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
            !_sameEpisode(selection, episode)) {
          return const SdkPlaybackOutcome('identity_mismatch');
        }
        final uri = media is Map && media['url'] is String
            ? Uri.tryParse(media['url'])
            : null;
        if (uri == null ||
            !const {'http', 'https'}.contains(uri.scheme) ||
            uri.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          return const SdkPlaybackOutcome('invalid_media');
        }
        final started = await open(episode, media as Map);
        if (cancelled()) return const SdkPlaybackOutcome('cancelled');
        if (started == null) {
          return SdkPlaybackOutcome('interaction_required', episode: episode);
        }
        if (started) {
          _record(line, clock.elapsedMilliseconds.toDouble(), success: true);
          return SdkPlaybackOutcome('ready', episode: episode);
        }
        _record(line, 30000);
        failureCode = 'MEDIA_LOAD_FAILED';
      } catch (error) {
        if (cancelled()) return const SdkPlaybackOutcome('cancelled');
        failureCode = error is SourceException
            ? error.code
            : error is TimeoutException
            ? 'TIMEOUT'
            : 'SOURCE_ERROR';
        _record(line, 30000);
      }
    }
    return SdkPlaybackOutcome('unavailable', errorCode: failureCode);
  }

  Future<List<SdkLineCandidate>> prepare(
    SdkEpisode? requested,
    List<SdkLine> lines,
    CancelToken cancel, {
    bool manual = false,
    bool confirmedSingleMovie = false,
  }) async {
    final generation = ++_probeGeneration;
    final unique = <String, SdkLine>{
      for (final line in lines) line.code: line,
    }.values.where((line) => !manual || line.code == requested?.code).toList();
    final results = <String, SdkLineCandidate>{};
    final probe = CancelToken();
    bool current() =>
        !_disposed &&
        !cancel.isCancelled &&
        !probe.isCancelled &&
        generation == _probeGeneration;
    unawaited(
      cancel.whenCancel.then((_) {
        if (!probe.isCancelled) probe.cancel();
      }),
    );
    bool verifiedMovie = confirmedSingleMovie && singleMovie;
    if (singleMovie && requested != null) {
      // 当前选集来自已加载的目录；没有缓存证据时保持严格匹配，避免串行等待原线路。
      final items = _cache[requested.code]?.items;
      verifiedMovie =
          verifiedMovie ||
          items?.length == 1 && items!.single.number == requested.number;
    }
    void publish() {
      if (!current()) return;
      candidates = [
        for (final line in unique)
          results[line.code] ?? SdkLineCandidate(line: line, status: 'loading'),
      ];
      onChanged?.call();
    }

    var next = 0;
    Future<void> worker() async {
      while (current() && next < unique.length) {
        final line = unique[next++];
        try {
          final items = await episodes(line).timeout(metadataBudget);
          if (!current()) return;
          final episode = requested == null
              ? items.firstOrNull
              : line.code == requested.code
              ? items
                    .where((item) => item.identityKey == requested.identityKey)
                    .firstOrNull
              : match(requested, items, singleMovie: verifiedMovie);
          if (episode == null) {
            results[line.code] = SdkLineCandidate(
              line: line,
              status: items.isEmpty ? 'empty' : 'mismatch',
            );
          } else {
            // 先保留已匹配的目录，画质超时不能把可播放线路变成无命中。
            results[line.code] = SdkLineCandidate(
              line: line,
              episode: episode,
              qualityStatus: service.supportsQualities ? 'loading' : 'unknown',
            );
            publish();
            List<SdkQuality> qualities = const [];
            var qualityStatus = 'unknown';
            if (service.supportsQualities) {
              try {
                qualities = await service
                    .qualitiesForEpisode(
                      videoId,
                      line.code,
                      episode,
                      cancel: probe,
                    )
                    .timeout(metadataBudget);
                qualityStatus = 'ready';
              } catch (error) {
                qualityStatus = error is TimeoutException
                    ? 'timeout'
                    : 'failed';
                /* 画质未知仍保留可重试的目录，不伪造清晰度。 */
              }
            }
            if (!current()) return;
            results[line.code] = SdkLineCandidate(
              line: line,
              episode: episode,
              qualities: qualities,
              qualityStatus: qualityStatus,
            );
          }
        } catch (error) {
          if (!current()) return;
          results[line.code] = SdkLineCandidate(
            line: line,
            status: error is TimeoutException ? 'timeout' : 'failed',
          );
        }
        publish();
      }
    }

    publish();
    try {
      await Future.any<void>([
        Future.wait(
          List.generate(unique.length < 3 ? unique.length : 3, (_) => worker()),
        ),
        cancel.whenCancel.then((_) {}),
      ]).timeout(metadataBudget);
    } on TimeoutException {
      /* 截止时尚未返回的线路明确标记，不能称为全部失效。 */
    }
    final valid =
        !_disposed && !cancel.isCancelled && generation == _probeGeneration;
    probe.cancel('metadata finished');
    if (!valid) return const [];
    candidates = unique.map((line) {
      final item =
          results[line.code] ?? SdkLineCandidate(line: line, status: 'timeout');
      // 总预算到期时，目录已经匹配的线路仍可播放，但画质不能永远停在加载中。
      return item.qualityStatus == 'loading'
          ? SdkLineCandidate(
              line: item.line,
              episode: item.episode,
              qualities: item.qualities,
              status: item.status,
              qualityStatus: 'timeout',
            )
          : item;
    }).toList();
    onChanged?.call();
    return candidates;
  }

  static bool _sameEpisode(Map selection, SdkEpisode episode) =>
      episode.reference != null
      ? selection['episodeRef'] == episode.reference
      : episode.number != null && selection['episodeNum'] == episode.number;

  /// 只解析当前同集候选，不打开播放器，也不登记首帧成功。
  Future<SdkPlaybackOutcome> preparePlayback(
    SdkEpisode requested,
    List<SdkLine> lines, {
    required CancelToken cancel,
    required FutureOr<void> Function(SdkLine, SdkEpisode, SdkQuality?)
    onAttempt,
    bool manual = false,
    String? qualityCode,
  }) => _runAutomatic(
    requested,
    lines,
    cancel: cancel,
    onAttempt: onAttempt,
    manual: manual,
    qualityCode: qualityCode,
  );

  Future<SdkPlaybackOutcome> playAutomatic(
    SdkEpisode requested,
    List<SdkLine> lines, {
    required CancelToken cancel,
    required FutureOr<void> Function(SdkLine, SdkEpisode, SdkQuality?)
    onAttempt,
    required Future<bool?> Function(
      SdkEpisode,
      Map<dynamic, dynamic>,
      CancelToken,
    )
    open,
    bool manual = false,
    PreparedPlayback? prepared,
    String? qualityCode,
  }) => _runAutomatic(
    requested,
    lines,
    cancel: cancel,
    onAttempt: onAttempt,
    manual: manual,
    open: open,
    prepared: prepared,
    qualityCode: qualityCode,
  );

  Future<SdkPlaybackOutcome> _runAutomatic(
    SdkEpisode requested,
    List<SdkLine> lines, {
    required CancelToken cancel,
    required FutureOr<void> Function(SdkLine, SdkEpisode, SdkQuality?)
    onAttempt,
    Future<bool?> Function(SdkEpisode, Map<dynamic, dynamic>, CancelToken)?
    open,
    bool manual = false,
    PreparedPlayback? prepared,
    String? qualityCode,
  }) async {
    bool cancelled() => _disposed || cancel.isCancelled;
    final clock = Stopwatch()..start();
    final choices = await prepare(requested, lines, cancel, manual: manual);
    if (cancelled()) return const SdkPlaybackOutcome('cancelled');
    final attempts = <({SdkLineCandidate candidate, SdkQuality? quality})>[];
    for (final candidate in choices.where((item) => item.episode != null)) {
      if (candidate.qualities.isEmpty) {
        if (qualityCode == null) {
          attempts.add((candidate: candidate, quality: null));
        }
      } else {
        final codes = <String>{};
        for (final quality in candidate.qualities) {
          if (codes.add(quality.code) &&
              (qualityCode == null || quality.code == qualityCode)) {
            attempts.add((candidate: candidate, quality: quality));
          }
        }
      }
    }
    final ranks = ranked(lines).map((line) => line.code).toList();
    attempts.sort((a, b) {
      final quality =
          (b.quality == null ? 0 : service.qualityPreference(b.quality!))
              .compareTo(
                a.quality == null ? 0 : service.qualityPreference(a.quality!),
              );
      return quality != 0
          ? quality
          : ranks
                .indexOf(a.candidate.line.code)
                .compareTo(ranks.indexOf(b.candidate.line.code));
    });
    var failure = qualityCode != null && attempts.isEmpty
        ? 'QUALITY_UNAVAILABLE'
        : 'PLAYBACK_UNAVAILABLE';
    for (var index = 0; index < attempts.length; index++) {
      if (cancelled()) return const SdkPlaybackOutcome('cancelled');
      if (clock.elapsed >= playbackBudget) {
        return SdkPlaybackOutcome(
          'unavailable',
          errorCode: 'ATTEMPT_BUDGET_EXHAUSTED',
          untried: attempts.length - index,
        );
      }
      final attempt = attempts[index], candidate = attempts[index].candidate;
      final episode = candidate.episode!;
      final attemptCancel = CancelToken();
      unawaited(
        cancel.whenCancel.then((_) {
          if (!attemptCancel.isCancelled) attemptCancel.cancel();
        }),
      );
      Duration remaining() => playbackBudget - clock.elapsed;
      try {
        await Future.sync(
          () => onAttempt(candidate.line, episode, attempt.quality),
        ).timeout(remaining());
        if (cancelled()) return const SdkPlaybackOutcome('cancelled');
        for (var refresh = 0; refresh < 2; refresh++) {
          Map media;
          if (refresh == 0 &&
              prepared != null &&
              prepared.isFresh(_now()) &&
              prepared.matches(
                providerId: service.id,
                contentId: videoId,
                lineCode: candidate.line.code,
                episodeIdentity: episode.identityKey,
                qualityCode: attempt.quality?.code,
              )) {
            media = prepared.media;
          } else {
            final result = await service
                .playEpisode(
                  videoId,
                  candidate.line.code,
                  episode,
                  quality: attempt.quality?.code,
                  cancel: attemptCancel,
                )
                .timeout(remaining());
            if (cancelled()) return const SdkPlaybackOutcome('cancelled');
            if (result['status'] == 'ad_required') {
              return const SdkPlaybackOutcome('ad_required');
            }
            if (result['status'] != 'ready') {
              failure = result['error'] is String
                  ? result['error']
                  : 'PLAYBACK_UNAVAILABLE';
              _record(candidate.line, 30000);
              break;
            }
            final selection = result['selection'], value = result['media'];
            if (selection is! Map ||
                selection['videoId'] != videoId ||
                selection['code'] != candidate.line.code ||
                !_sameEpisode(selection, episode)) {
              return const SdkPlaybackOutcome('identity_mismatch');
            }
            if (value is! Map) {
              failure = 'INVALID_MEDIA';
              break;
            }
            media = value;
          }
          final uri = media['url'] is String
              ? Uri.tryParse(media['url'])
              : null;
          if (uri == null ||
              !['http', 'https'].contains(uri.scheme) ||
              uri.host.isEmpty ||
              uri.userInfo.isNotEmpty) {
            failure = 'INVALID_MEDIA';
            break;
          }
          if (open == null) {
            return SdkPlaybackOutcome(
              'prepared',
              episode: episode,
              quality: attempt.quality,
              prepared: PreparedPlayback(
                providerId: service.id,
                contentId: videoId,
                lineCode: candidate.line.code,
                episodeIdentity: episode.identityKey,
                qualityCode: attempt.quality?.code,
                resolvedAt: _now(),
                media: media,
              ),
            );
          }
          final startedAt = Stopwatch()..start();
          bool? started;
          try {
            started = await open(
              episode,
              media,
              attemptCancel,
            ).timeout(remaining());
          } on SourceException catch (error) {
            // 短效地址拒绝时只在原同集同线路刷新一次，手动锁定范围不扩大。
            if (error.code == 'EXPIRED' && refresh == 0 && !cancelled()) {
              continue;
            }
            rethrow;
          }
          if (cancelled()) return const SdkPlaybackOutcome('cancelled');
          if (started == null || started) {
            if (started == true) {
              _record(
                candidate.line,
                startedAt.elapsedMilliseconds.toDouble(),
                success: true,
              );
            }
            return SdkPlaybackOutcome(
              started == null ? 'interaction_required' : 'ready',
              episode: episode,
              quality: attempt.quality,
            );
          }
          failure = 'MEDIA_LOAD_FAILED';
          _record(candidate.line, 30000);
          break;
        }
      } catch (error) {
        if (cancelled()) return const SdkPlaybackOutcome('cancelled');
        if (error is TimeoutException) {
          attemptCancel.cancel('playback budget exhausted');
          return SdkPlaybackOutcome(
            'unavailable',
            errorCode: 'ATTEMPT_BUDGET_EXHAUSTED',
            untried: attempts.length - index - 1,
          );
        }
        failure = error is SourceException
            ? error.code
            : error is TimeoutException
            ? 'TIMEOUT'
            : 'SOURCE_ERROR';
      }
    }
    if (attempts.isEmpty && choices.any((item) => item.status == 'timeout')) {
      failure = 'TIMEOUT';
    }
    return SdkPlaybackOutcome('unavailable', errorCode: failure);
  }

  void dispose() {
    _disposed = true;
    _probeGeneration++;
    _lifetime.cancel('Playback session disposed');
    _cache.clear();
  }
}
