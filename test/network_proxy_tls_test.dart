import 'dart:io';

import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/services/storage/storage.dart';

class _ProbeClient implements HttpClient {
  bool Function(X509Certificate, String, int)? certificateCallback;
  String Function(Uri)? proxyResolver;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate, String, int)? value,
  ) => certificateCallback = value;
  @override
  set findProxy(String Function(Uri)? value) => proxyResolver = value;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory data;
  setUpAll(() async {
    data = await Directory.systemTemp.createTemp('playra-proxy-tls-test-');
    Hive.init(data.path);
    await GStorage.init();
  });
  tearDownAll(() async {
    await GStorage.close();
    await data.delete(recursive: true);
  });

  test(
    'enabling a manual proxy preserves TLS certificate verification',
    () async {
      await GStorage.putSetting(SettingsKeys.proxyUrl, '127.0.0.1:7890');
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      final config = NetworkConfig.fromSettings();
      expect(config.hasProxy, isTrue);
      expect(config.allowBadCertificates, isFalse);
      final adapter = config.createAdapter() as IOHttpClientAdapter;
      final probe = _ProbeClient();
      final client = HttpOverrides.runZoned(
        adapter.createHttpClient!,
        createHttpClient: (_) => probe,
      );
      expect(client, same(probe));
      expect(probe.certificateCallback, isNull);
      expect(
        probe.proxyResolver!(Uri.parse('https://example.com')),
        'PROXY 127.0.0.1:7890',
      );
    },
  );
}
