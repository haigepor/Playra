import 'dart:io';
import 'package:dio/io.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/network/system_proxy_service.dart';

IOHttpClientAdapter createNetworkAdapter(NetworkConfig config) =>
    IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        if (config.hasProxy) {
          client.findProxy = (_) =>
              'PROXY ${config.proxyHost}:${config.proxyPort}';
        } else if (Platform.isWindows) {
          client.findProxy = SystemProxyService.findProxy;
        }
        if (config.allowBadCertificates) {
          client.badCertificateCallback = (cert, host, port) => true;
        }
        return client;
      },
    );
