import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';
import 'package:kazumi/services/platform/platform_io.dart';
import 'package:kazumi/services/storage/storage.dart';

/// 带系统/手动代理的图片缓存。空壳不包含任何来源镜像或 ECH 逻辑。
class ProxyAwareImageCacheManager extends CacheManager with ImageCacheManager {
  static final ProxyAwareImageCacheManager instance =
      ProxyAwareImageCacheManager._();

  ProxyAwareImageCacheManager._()
    : super(
        Config(
          DefaultCacheManager.key,
          fileService: _ProxyAwareHttpFileService(),
        ),
      );

  /// 代理设置变更后由 ProxyManager 调用；文件服务会在下一次请求时根据
  /// [NetworkConfig.revision] 自动切换 HttpClient。
  void resetNetworkClients() {}

  static IOClient _createHttpClient() {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    final proxy = _currentProxy();
    if (proxy != null) {
      client.findProxy = (_) => 'PROXY ${proxy.$1}:${proxy.$2}';
      client.badCertificateCallback = (cert, host, port) => true;
    } else if (Platform.isWindows) {
      client.findProxy = SystemProxyService.findProxy;
    }
    return IOClient(client);
  }

  static (String, int)? _currentProxy() {
    if (!GStorage.getSetting(SettingsKeys.proxyEnable)) return null;

    final proxyUrl = GStorage.getSetting(SettingsKeys.proxyUrl);
    final parsed = ProxyUtils.parseProxyUrl(proxyUrl);
    if (parsed == null) {
      KazumiLogger().w('Proxy: 图片缓存代理地址格式错误或为空');
    }
    return parsed;
  }
}

/// File service that keeps its HTTP client in sync with proxy settings.
class _ProxyAwareHttpFileService extends FileService {
  http.Client? _client;
  int _revision = -1;

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    final client = _clientForCurrentConfig();
    final request = http.Request('GET', Uri.parse(url));
    if (headers != null) request.headers.addAll(headers);
    return HttpGetResponse(await client.send(request));
  }

  http.Client _clientForCurrentConfig() {
    final revision = NetworkConfig.revision;
    if (_client == null || _revision != revision) {
      _client?.close();
      _client = ProxyAwareImageCacheManager._createHttpClient();
      _revision = revision;
    }
    return _client!;
  }
}
