import 'package:ech_http/ech_http.dart';
import 'package:http/http.dart' as http;

class BangumiEchResolver {
  BangumiEchResolver._();

  static final endpoint = Uri.https('dns.alidns.com', '/resolve');
  // 共享给 Android 和无 Flutter engine 的本机 Web 网关。
  static const hosts = {'api.bgm.tv', 'next.bgm.tv', 'lain.bgm.tv'};
  static const _addresses = ['172.67.134.140', '104.21.6.61', '172.67.73.67'];

  static DohEchResolver create(http.Client bootstrap) => DohEchResolver(
    client: bootstrap,
    endpoint: endpoint,
    hosts: hosts,
    // Shared Cloudflare ECH config and pinned IPs bypass polluted Bangumi DNS.
    configDomains: {for (final host in hosts) host: 'crypto.cloudflare.com'},
    addressOverrides: {for (final host in hosts) host: _addresses},
  );
}
