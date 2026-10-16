import 'lumina_support_stub.dart'
    if (dart.library.io) 'lumina_support_io.dart' as platform;

/// 无原生产物的平台不登记本地 Lumina，不尝试仿真或引入第三方依赖。
bool get luminaSupported => platform.luminaSupported;
