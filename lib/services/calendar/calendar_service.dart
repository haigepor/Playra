import 'package:dio/dio.dart';
import 'package:kazumi/request/clients/bangumi_client.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/network/bangumi_acceleration.dart';
import 'calendar_models.dart';

typedef CalendarGet =
    Future<dynamic> Function(
      String url, {
      Map<String, dynamic>? queryParameters,
      CancelToken? cancelToken,
    });
typedef CalendarPost =
    Future<dynamic> Function(
      String url, {
      Object? data,
      Map<String, dynamic>? queryParameters,
      CancelToken? cancelToken,
    });

/// 元数据排期服务独立于页面与播放源；沿用已有跨平台网络传输。
class CalendarService {
  CalendarService({
    CalendarGet? get,
    CalendarPost? post,
    bool Function()? useMirror,
    DateTime Function()? clock,
  }) : _get =
           get ??
           ((url, {queryParameters, cancelToken}) => BangumiClient.instance.get(
             url,
             queryParameters: queryParameters,
             cancelToken: cancelToken,
           )),
       _post =
           post ??
           ((url, {data, queryParameters, cancelToken}) =>
               BangumiClient.instance.post(
                 url,
                 data: data,
                 queryParameters: queryParameters,
                 cancelToken: cancelToken,
               )),
       _useMirror =
           useMirror ??
           (() => BangumiAcceleration.current == BangumiAcceleration.mirror),
       _clock = clock ?? DateTime.now;

  static final instance = CalendarService();
  final CalendarGet _get;
  final CalendarPost _post;
  final bool Function() _useMirror;
  final DateTime Function() _clock;
  final _cache = <String, (DateTime, SeasonScheduleSnapshot)>{};
  final _details = <int, (DateTime, Map<String, dynamic>)>{};
  String _key(DateTime season) => '${_useMirror()}:${calendarSeason(season)}';

  SeasonScheduleSnapshot? cached(DateTime season) => _cache[_key(season)]?.$2;

  Future<SeasonScheduleSnapshot> load(
    DateTime date, {
    bool force = false,
    CancelToken? cancelToken,
  }) async {
    final season = calendarSeason(date);
    final key = _key(season);
    final cached = _cache[key];
    if (!force &&
        cached != null &&
        _clock().difference(cached.$1) < const Duration(minutes: 30)) {
      return cached.$2;
    }
    SeasonScheduleSnapshot result;
    if (season == calendarSeason(_clock())) {
      result = parseCalendarSnapshot(
        await _get(
          '${ApiEndpoints.bangumiAPINextDomain}${ApiEndpoints.bangumiCalendar}',
          cancelToken: cancelToken,
        ),
        season: season,
      );
    } else if (_useMirror()) {
      final path = Uri(
        path: ApiEndpoints.bangumiMirrorSeasonCalendar,
        queryParameters: {
          'start': _date(season),
          'end': _date(DateTime(season.year, season.month + 3)),
        },
      );
      result = parseCalendarSnapshot(
        await _get(
          '${ApiEndpoints.bangumiMirrorDomain}$path',
          cancelToken: cancelToken,
        ),
        season: season,
        source: 'Bangumi 镜像',
      );
    } else {
      result = await _loadHistory(season, cancelToken);
    }
    if (cancelToken?.isCancelled ?? false) throw const CalendarCancelled();
    if (_cache.length >= 8 && !_cache.containsKey(key)) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = (_clock(), result);
    return result;
  }

  Future<SeasonScheduleSnapshot> _loadHistory(
    DateTime season,
    CancelToken? token,
  ) async {
    final entries = <ScheduleEntry>[];
    final seen = <int>{};
    var partial = false;
    const limit = 50, maximum = 500;
    for (var offset = 0; offset < maximum; offset += limit) {
      dynamic raw;
      try {
        raw = await _post(
          '${ApiEndpoints.bangumiAPIDomain}/v0/search/subjects',
          queryParameters: {'limit': limit, 'offset': offset},
          cancelToken: token,
          data: {
            'keyword': '',
            'sort': 'rank',
            'filter': {
              'type': [2],
              'air_date': [
                '>=${_date(season)}',
                '<${_date(DateTime(season.year, season.month + 3))}',
              ],
            },
          },
        );
        if (raw is! Map || raw['data'] is! List) {
          throw const FormatException('季度响应格式异常');
        }
      } catch (_) {
        if ((token?.isCancelled ?? false) || entries.isEmpty) rethrow;
        partial = true;
        break;
      }
      final list = raw['data'] as List;
      for (final item in list) {
        try {
          final entry = parseScheduleEntry(
            Map<String, dynamic>.from(item as Map),
          );
          if (seen.add(entry.item.id)) entries.add(entry);
        } catch (_) {
          partial = true;
        }
      }
      final total = raw['total'];
      if (list.length < limit ||
          total is num && offset + list.length >= total) {
        break;
      }
      if (offset + limit >= maximum) partial = true;
    }
    return SeasonScheduleSnapshot(
      season: season,
      entries: List.unmodifiable(entries),
      source: 'Bangumi 季度条目',
      partial: partial,
      notice: partial ? '季度数据尚未完整获取，已保留可用内容' : null,
    );
  }

  Future<ScheduleEntry> enrich(
    ScheduleEntry entry, {
    bool force = false,
    CancelToken? cancelToken,
  }) async {
    final cached = _details[entry.item.id];
    Map<String, dynamic> raw;
    if (!force &&
        cached != null &&
        _clock().difference(cached.$1) < const Duration(hours: 24)) {
      raw = cached.$2;
    } else {
      final response = await _get(
        '${ApiEndpoints.bangumiAPINextDomain}/p1/subjects/${entry.item.id}',
        cancelToken: cancelToken,
      );
      if (response is! Map) throw const FormatException('番剧详情格式异常');
      raw = Map<String, dynamic>.from(response);
      if (cancelToken?.isCancelled ?? false) throw const CalendarCancelled();
      if (_details.length >= 500) _details.remove(_details.keys.first);
      _details[entry.item.id] = (_clock(), raw);
    }
    return entry.withDetail(raw);
  }

  String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

class CalendarCancelled implements Exception {
  const CalendarCancelled();
}
