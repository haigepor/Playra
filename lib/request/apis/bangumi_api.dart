import 'package:kazumi/services/source/source_models.dart' show SourceException;
import 'package:dio/dio.dart' show CancelToken;
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/modules/bangumi/bangumi_relation.dart';
import 'package:kazumi/modules/comments/comment_response.dart';
import 'package:kazumi/modules/characters/characters_response.dart';
import 'package:kazumi/modules/bangumi/episode_item.dart';
import 'package:kazumi/modules/character/character_full_item.dart';
import 'package:kazumi/modules/staff/staff_response.dart';
import 'package:kazumi/modules/bangumi/bangumi_collection.dart';
import 'package:kazumi/modules/bangumi/bangumi_collection_type.dart';
import 'package:kazumi/modules/comments/comment_item.dart';
import 'package:kazumi/utils/search_parser.dart';

class BangumiSearchPage {
  const BangumiSearchPage({required this.items, required this.rawCount});

  final List<BangumiItem> items;
  final int rawCount;
}

class BangumiApi {
  static Future<List<List<BangumiItem>>> getCalendar() async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  // Official fallback for season switching. Mirror mode uses the cached
  // /kazumi/v1/calendar/season endpoint instead of Bangumi search.
  static Future<List<List<BangumiItem>>> getCalendarBySearch(
    List<String> dateRange,
    int limit,
    int offset,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static String buildBangumiMirrorSeasonCalendarPath(List<String> dateRange) {
    return Uri(
      path: ApiEndpoints.bangumiMirrorSeasonCalendar,
      queryParameters: {'start': dateRange[0], 'end': dateRange[1]},
    ).toString();
  }

  static Future<List<List<BangumiItem>>> getBangumiMirrorSeasonCalendar(
    List<String> dateRange,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<List<BangumiItem>> getBangumiList({
    int rank = 2,
    String tag = '',
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<List<BangumiItem>> getBangumiTrendsList({
    int type = 2,
    int limit = 24,
    int offset = 0,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static String buildBangumiMirrorPopularPath({
    String tag = '',
    int limit = 24,
    int offset = 0,
  }) {
    return Uri(
      path: ApiEndpoints.bangumiMirrorPopularSubjects,
      queryParameters: {
        if (tag.isNotEmpty) 'tag': tag,
        'limit': limit.toString(),
        'offset': offset.toString(),
      },
    ).toString();
  }

  static Future<List<BangumiItem>> getBangumiMirrorPopularSubjects({
    String tag = '',
    int limit = 24,
    int offset = 0,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static List<String> _buildNumberFilter<T extends num>(T? min, T? max) {
    return [if (min != null) '>=$min', if (max != null) '<=$max'];
  }

  static Map<String, dynamic> buildBangumiSearchParams(
    String keyword, {
    List<String> tags = const [],
    String sort = 'heat',
    SearchDateRange? dateRange,
    SearchIntRange? rankRange,
    SearchDoubleRange? scoreRange,
    List<int> weekdays = const [],
  }) {
    final rankFilter = rankRange?.isValid == true
        ? _buildNumberFilter<int>(rankRange!.min, rankRange.max)
        : (sort == 'rank')
        ? [">0", "<=99999"]
        : [">=0", "<=99999"];

    final filter = <String, dynamic>{
      "type": [2],
      "tag": tags,
      "rank": rankFilter,
      "nsfw": false,
    };

    if (dateRange?.isValid == true) {
      filter["air_date"] = [">=${dateRange!.start}", "<${dateRange.end}"];
    }
    if (scoreRange?.isValid == true) {
      filter["rating"] = _buildNumberFilter<double>(
        scoreRange!.min,
        scoreRange.max,
      );
    }
    if (weekdays.isNotEmpty) {
      filter["air_weekday"] = weekdays.toSet().toList()..sort();
    }

    return <String, dynamic>{
      'keyword': keyword,
      'sort': sort,
      "filter": filter,
    };
  }

  static Future<BangumiSearchPage?> bangumiSearch(
    String keyword, {
    List<String> tags = const [],
    int limit = 20,
    int offset = 0,
    String sort = 'heat',
    SearchDateRange? dateRange,
    SearchIntRange? rankRange,
    SearchDoubleRange? scoreRange,
    List<int> weekdays = const [],
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<BangumiItem?> getBangumiInfoByID(int id) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<List<BangumiRelation>> getBangumiRelationsByID(int id) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<EpisodeInfo> getBangumiEpisodeByID(int id, int episode) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<List<EpisodeInfo>> getBangumiEpisodesByID(
    int id, {
    bool throwOnError = false,
    CancelToken? cancelToken,
    void Function(List<EpisodeInfo>)? onPage,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<CommentResponse> getBangumiCommentsByID(
    int id, {
    int offset = 0,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<EpisodeCommentResponse> getBangumiCommentsByEpisodeID(
    int id,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<CharacterCommentResponse> getCharacterCommentsByCharacterID(
    int id,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<StaffResponse> getBangumiStaffByID(int id) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<CharactersResponse> getCharatersByBangumiID(int id) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<CharacterFullItem> getCharacterByCharacterID(int id) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<User?> getCurrentUser({String? accessToken}) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<List<BangumiCollection>> getBangumiCollectibles({
    List<BangumiCollectionType> includeBangumiTypes = const [
      BangumiCollectionType.planToWatch,
      BangumiCollectionType.watched,
      BangumiCollectionType.watching,
      BangumiCollectionType.onHold,
      BangumiCollectionType.abandoned,
    ],
    required String username,
    int limit = 50,
    void Function(String message, int current, int total)? onProgress,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<bool> updateBangumiById(
    int id,
    Map<String, dynamic> data,
  ) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<bool> updateBangumiByType(int id, int localType) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static Future<bool> addOrUpdateBangumiEvaluationBySubjectID(
    int subjectID,
    int localType, {
    String? comment,
    int? rate,
    List<String>? tags,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }
}
