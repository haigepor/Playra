import 'package:kazumi/services/source/source_models.dart' show SourceException;
import 'package:kazumi/services/platform/platform_io.dart';

import 'package:kazumi/modules/search/image_search_module.dart';

class TraceApi {
  ///根据图片搜索番剧信息
  static Future<ImageSearchItem> searchAnimeByImageFile(
    File imageFile, {
    int anilistInfo = 2,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  ///根据图片URL搜索番剧信息
  static Future<ImageSearchItem> searchAnimeByImageUrl(
    String imageUrl, {
    int anilistInfo = 2,
  }) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }
}
