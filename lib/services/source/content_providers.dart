import 'content_search.dart';
import 'hongguo/hongguo_content_provider.dart';
import 'hongguo/hongguo_env.dart';
import 'lumina/lumina_content_provider.dart';
import 'lumina/lumina_service.dart';
import 'package:kazumi/services/platform/lumina_support.dart';

/// 不支持原生引擎的平台保持空集合，不注册其他来源作为回退。
/// 红果为纯 Dart 协议，全平台可用；客户端由 HongguoEnv 进程级共享。
List<ContentSearchProvider> contentProviders({LuminaService? lumina}) => [
  if (luminaSupported) LuminaContentProvider(lumina ?? LuminaService()),
  HongguoContentProvider(HongguoEnv.shared),
];
