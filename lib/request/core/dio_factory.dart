import 'package:dio/dio.dart';
import 'package:kazumi/request/core/dio_logger_interceptor.dart';
import 'package:kazumi/request/core/network_config.dart';

/// 空壳保留的唯一 Dio 入口：新数据源按需注入自己的 BaseOptions。
///
/// 不预置任何来源域名、拦截器或镜像规则；代理与证书策略来自
/// [NetworkConfig.fromSettings]。
class DioFactory {
  DioFactory._();

  static Dio? _apiDio;

  static Dio get apiDio =>
      _apiDio ??= createForConfig(NetworkConfig.fromSettings());

  static Dio createForConfig(NetworkConfig config) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: config.connectTimeout,
        receiveTimeout: config.receiveTimeout,
        sendTimeout: config.sendTimeout,
        validateStatus: (status) =>
            status != null && status >= 200 && status < 300,
      ),
    );
    dio.httpClientAdapter = config.createAdapter();
    if (config.enableLog) {
      dio.interceptors.add(DioLoggerInterceptor());
    }
    return dio;
  }

  static void reset() {
    _apiDio?.close();
    _apiDio = null;
  }
}
