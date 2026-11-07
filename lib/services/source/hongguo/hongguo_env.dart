/// 红果源的共享环境：进程内单例客户端 + 设备档案落盘。
/// 首页、搜索、个人库共用同一台匿名设备与传输层。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'hongguo_client.dart';
import 'hongguo_device.dart';

class HongguoEnv {
  HongguoEnv._();

  static HongguoClient? _client;

  /// 共享客户端。档案存应用支持目录（不参与系统备份语义由调用方决定）。
  static HongguoClient get shared {
    final existing = _client;
    if (existing != null) return existing;
    final client = HongguoClient(
      profileStore: _fileStore(),
    );
    _client = client;
    return client;
  }

  static HongguoProfileStore _fileStore() {
    if (kIsWeb) {
      // Web 没有文件系统；档案只保存在内存里（每次冷启动重新注册）。
      return HongguoMemoryProfileStore();
    }
    return HongguoFileStoreDeferred();
  }
}

/// 文件档案库：目录在首次 IO 时异步解析（main 之后才能调 path_provider）。
class HongguoFileStoreDeferred implements HongguoProfileStore {
  HongguoFileProfileStore? _resolved;

  Future<HongguoFileProfileStore> _store() async {
    final resolved = _resolved;
    if (resolved != null) return resolved;
    final base = await getApplicationSupportDirectory();
    final store = HongguoFileProfileStore(
      Directory('${base.path}/hongguo'),
    );
    _resolved = store;
    return store;
  }

  @override
  Future<HongguoDeviceProfile?> load() async => (await _store()).load();

  @override
  Future<void> save(HongguoDeviceProfile profile) async =>
      (await _store()).save(profile);

  @override
  Future<void> reset() async => (await _store()).reset();
}
