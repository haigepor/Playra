/// 红果匿名设备身份与档案存储（对标 openhongguo sdk/device.go + model/device.go）。
/// 纯 Dart；存储实现由调用方注入（App 用文件，测试/探针用内存）。
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// 匿名身份出示的手机。注册体、请求 query 和 UA 都描述它。
class HongguoDevice {
  const HongguoDevice({
    this.brand = '',
    this.model = '',
    this.osVersion = '',
    this.osApi = 0,
    this.build = '',
    this.resolution = '',
    this.dpi = 0,
    this.pad = false,
    this.channel = '',
  });

  const HongguoDevice.defaults()
      : this(
          brand: 'Xiaomi',
          model: '23127PN0CC',
          osVersion: '14',
          osApi: 34,
          build: 'UKQ1.230804.001',
          resolution: '1200*2670',
          dpi: 460,
          channel: 'xiaomi_8662_64',
        );

  factory HongguoDevice.fromJson(Map<String, dynamic> j) => HongguoDevice(
        brand: j['brand'] ?? '',
        model: j['model'] ?? '',
        osVersion: j['os_version'] ?? '',
        osApi: j['os_api'] ?? 0,
        build: j['build'] ?? '',
        resolution: j['resolution'] ?? '',
        dpi: j['dpi'] ?? 0,
        pad: j['pad'] ?? false,
        channel: j['channel'] ?? '',
      );

  final String brand;
  final String model;
  final String osVersion;
  final int osApi;
  final String build;
  final String resolution;
  final int dpi;
  final bool pad;
  final String channel;

  Map<String, dynamic> toJson() => {
        'brand': brand,
        'model': model,
        'os_version': osVersion,
        'os_api': osApi,
        'build': build,
        'resolution': resolution,
        'dpi': dpi,
        'pad': pad,
        'channel': channel,
      };

  /// 空字段取默认机型（Xiaomi 14 / Android 14 / 小米商店渠道）。
  HongguoDevice orDefault() => HongguoDevice(
        brand: brand.isEmpty ? 'Xiaomi' : brand,
        model: model.isEmpty ? '23127PN0CC' : model,
        osVersion: osVersion.isEmpty ? '14' : osVersion,
        osApi: osApi == 0 ? 34 : osApi,
        build: build.isEmpty ? 'UKQ1.230804.001' : build,
        resolution: resolution.isEmpty ? '1200*2670' : resolution,
        dpi: dpi == 0 ? 460 : dpi,
        pad: pad,
        channel: channel.isEmpty ? 'xiaomi_8662_64' : channel,
      );
}

/// 签名 query 的身份：注册分配的 id + 注册时的机型。
class HongguoSearchIdentity {
  const HongguoSearchIdentity({
    required this.deviceId,
    required this.installId,
    required this.cdId,
    required this.openUdId,
    required this.device,
  });

  final String deviceId;
  final String installId;
  final String cdId;
  final String openUdId;
  final HongguoDevice device;
}

/// 本地生成的匿名安装。device_id/install_id 由注册分配。
class HongguoDeviceProfile {
  HongguoDeviceProfile({
    required this.cdId,
    required this.openUdId,
    required this.clientUdId,
    required this.oaId,
    required this.reqId,
    required this.createdAt,
    this.deviceId = '',
    this.installId = '',
    this.deviceToken = '',
    this.ttReq = '',
    this.storeRegion = '',
    this.storeRegionSrc = '',
    HongguoDevice? device,
  }) : device = device ?? const HongguoDevice.defaults();

  factory HongguoDeviceProfile.fromJson(Map<String, dynamic> j) {
    return HongguoDeviceProfile(
      cdId: j['cdid'] ?? '',
      openUdId: j['openudid'] ?? '',
      clientUdId: j['clientudid'] ?? '',
      oaId: j['oaid_id'] ?? '',
      reqId: j['req_id'] ?? '',
      deviceId: j['device_id_str'] ?? '',
      installId: j['install_id_str'] ?? '',
      deviceToken: j['device_token'] ?? '',
      ttReq: j['ttreq'] ?? '',
      storeRegion: j['store_region'] ?? '',
      storeRegionSrc: j['store_region_src'] ?? '',
      createdAt: DateTime.tryParse(j['created_at'] ?? '') ?? DateTime.now().toUtc(),
      device: j['device'] == null
          ? null
          : HongguoDevice.fromJson((j['device'] as Map<String, dynamic>)),
    );
  }

  String cdId;
  String openUdId;
  String clientUdId;
  String oaId;
  String reqId;
  String deviceId;
  String installId;
  String deviceToken;
  String ttReq;
  String storeRegion;
  String storeRegionSrc;
  DateTime createdAt;
  HongguoDevice device;

  Map<String, dynamic> toJson() => {
        'cdid': cdId,
        'openudid': openUdId,
        'clientudid': clientUdId,
        'oaid_id': oaId,
        'req_id': reqId,
        if (deviceId.isNotEmpty) 'device_id_str': deviceId,
        if (installId.isNotEmpty) 'install_id_str': installId,
        if (deviceToken.isNotEmpty) 'device_token': deviceToken,
        if (ttReq.isNotEmpty) 'ttreq': ttReq,
        if (storeRegion.isNotEmpty) 'store_region': storeRegion,
        if (storeRegionSrc.isNotEmpty) 'store_region_src': storeRegionSrc,
        'created_at': createdAt.toUtc().toIso8601String(),
        'device': device.toJson(),
      };

  bool get ready =>
      deviceId.isNotEmpty &&
      installId.isNotEmpty &&
      deviceId != '0' &&
      installId != '0';

  String get guestCookie =>
      'passport_csrf_token=; passport_csrf_token_default=; '
      'store-region=$storeRegion; store-region-src=$storeRegionSrc; '
      'install_id=$installId; ttreq=$ttReq';
}

/// 用安全随机数填充身份字段（sdk/device.go NewAnonymousDeviceProfile）。
HongguoDeviceProfile newAnonymousDeviceProfile({
  DateTime? createdAt,
  Random? entropy,
}) {
  final rng = entropy ?? Random.secure();
  final raw = Uint8List(72);
  for (var i = 0; i < raw.length; i++) {
    raw[i] = rng.nextInt(256);
  }
  return HongguoDeviceProfile(
    cdId: _uuid(raw.sublist(0, 16)),
    openUdId: _hexLower(raw.sublist(16, 24)),
    clientUdId: _uuid(raw.sublist(24, 40)),
    oaId: _uuid(raw.sublist(40, 56)),
    reqId: _uuid(raw.sublist(56, 72)),
    createdAt: createdAt ?? DateTime.now().toUtc(),
  );
}

String _hexLower(List<int> bytes) {
  final sb = StringBuffer();
  for (final b in bytes) {
    sb.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}

String _uuid(List<int> bytes) {
  final id = Uint8List(16);
  id.setRange(0, 16, bytes);
  id[6] = (id[6] & 0x0f) | 0x40;
  id[8] = (id[8] & 0x3f) | 0x80;
  final s = StringBuffer();
  void hex(int start, int end) {
    for (var i = start; i < end; i++) {
      s.write(id[i].toRadixString(16).padLeft(2, '0'));
    }
  }

  hex(0, 4);
  s.write('-');
  hex(4, 6);
  s.write('-');
  hex(6, 8);
  s.write('-');
  hex(8, 10);
  s.write('-');
  hex(10, 16);
  return s.toString();
}

/// 注册请求的本地身份半边（register.go RegisterIdentity）。
class HongguoRegisterIdentity {
  const HongguoRegisterIdentity({
    required this.cdId,
    required this.openUdId,
    required this.clientUdId,
    required this.oaId,
    required this.reqId,
    required this.device,
  });

  final String cdId;
  final String openUdId;
  final String clientUdId;
  final String oaId;
  final String reqId;
  final HongguoDevice device;
}

/// 档案持久化接口（openhot ProfileStore）。
abstract class HongguoProfileStore {
  /// 返回 null 表示没有档案（首次使用）。
  Future<HongguoDeviceProfile?> load();
  Future<void> save(HongguoDeviceProfile profile);
  Future<void> reset();
}

/// 内存版：测试与探针用。
class HongguoMemoryProfileStore implements HongguoProfileStore {
  HongguoDeviceProfile? _profile;

  @override
  Future<HongguoDeviceProfile?> load() async => _profile;

  @override
  Future<void> save(HongguoDeviceProfile profile) async => _profile = profile;

  @override
  Future<void> reset() async => _profile = null;
}

/// 文件版：单 JSON 文件；[dir] 由调用方给（App 支持目录 / 探针临时目录）。
class HongguoFileProfileStore implements HongguoProfileStore {
  HongguoFileProfileStore(this.dir, {this.fileName = 'hongguo_anonymous.json'});

  final Directory dir;
  final String fileName;

  File get _file => File('${dir.path}/$fileName');

  @override
  Future<HongguoDeviceProfile?> load() async {
    if (!await _file.exists()) return null;
    try {
      final text = await _file.readAsString();
      if (text.trim().isEmpty) return null;
      return HongguoDeviceProfile.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(HongguoDeviceProfile profile) async {
    await dir.create(recursive: true);
    await _file.writeAsString(jsonEncode(profile.toJson()));
  }

  @override
  Future<void> reset() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}
