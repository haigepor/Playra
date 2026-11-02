import 'content_search.dart';
import 'lumina/lumina_content_provider.dart';
import 'lumina/lumina_service.dart';
import 'package:kazumi/services/platform/lumina_support.dart';

/// 不支持原生引擎的平台保持空集合，不注册其他来源作为回退。
List<ContentSearchProvider> contentProviders({LuminaService? lumina}) => [
  if (luminaSupported) LuminaContentProvider(lumina ?? LuminaService()),
];
