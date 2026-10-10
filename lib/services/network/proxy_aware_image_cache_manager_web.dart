import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class ProxyAwareImageCacheManager extends CacheManager with ImageCacheManager {
  static final instance = ProxyAwareImageCacheManager._();
  ProxyAwareImageCacheManager._() : super(Config(DefaultCacheManager.key));
  void resetNetworkClients() {}
}
