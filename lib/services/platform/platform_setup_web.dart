import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'browser_file_system.dart';

void configurePlatformPaths() {
  PathProviderPlatform.instance = _BrowserPaths();
}

Future<void> initializePlatformFiles() => initializeBrowserFiles();

/// 这些路径属于 IndexedDB 虚拟文件系统，不代表宿主电脑的真实目录。
class _BrowserPaths extends PathProviderPlatform {
  @override
  Future<String> getTemporaryPath() async => '/kazumi/tmp';
  @override
  Future<String> getApplicationSupportPath() async => '/kazumi';
  @override
  Future<String> getApplicationDocumentsPath() async => '/kazumi/documents';
  @override
  Future<String> getApplicationCachePath() async => '/kazumi/cache';
  @override
  Future<String> getDownloadsPath() async => '/kazumi/downloads';
}
