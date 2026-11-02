import 'package:kazumi/services/source/source_models.dart' show SourceException;
import 'dart:convert';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/modules/plugin/plugin_http_module.dart';

class PluginCatalogApi {
  static Future<List<PluginHTTPItem>> getPluginList() async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }

  static PluginCatalogParseResult parsePluginList(String raw) {
    final jsonData = json.decode(raw);
    if (jsonData is! List) {
      throw const FormatException('Rule catalog root must be a JSON array');
    }
    final items = <PluginHTTPItem>[];
    var skippedItems = 0;
    for (var index = 0; index < jsonData.length; index++) {
      try {
        items.add(_parsePluginListItem(jsonData[index], index));
      } on FormatException {
        skippedItems++;
      }
    }
    if (jsonData.isNotEmpty && items.isEmpty) {
      throw const FormatException('Rule catalog contains no valid items');
    }
    return PluginCatalogParseResult(
      items: List.unmodifiable(items),
      skippedItems: skippedItems,
    );
  }

  static PluginHTTPItem _parsePluginListItem(Object? value, int index) {
    if (value is! Map) {
      throw FormatException('Rule catalog item $index must be an object');
    }
    try {
      return PluginHTTPItem.fromJson(Map<String, dynamic>.from(value));
    } catch (error) {
      throw FormatException('Invalid rule catalog item $index: $error');
    }
  }

  static Future<Plugin> getPlugin(String name) async {
    throw const SourceException('SOURCE_REMOVED', '当前仅保留 Lumina 数据源');
  }
}

class PluginCatalogParseResult {
  const PluginCatalogParseResult({
    required this.items,
    required this.skippedItems,
  });

  final List<PluginHTTPItem> items;
  final int skippedItems;
}
