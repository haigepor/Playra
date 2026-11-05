import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kazumi/services/network/bangumi_ech_image_service.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/network/image_file_service.dart';

void main() {
  ImageFileService serviceWith(http.Client client) => ImageFileService(
    acceleration: () => ImageAcceleration.direct,
    clientFactory: () => client,
    echService: BangumiEchImageService(proxyForUrl: (_) => null),
  );

  test('直连异常时自动改用镜像，后续请求优先走镜像', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      if (request.url.host == 'wsrv.nl') {
        return http.Response.bytes([1, 2, 3], 200);
      }
      throw const SocketExceptionLike('connection reset');
    });
    final service = serviceWith(client);

    final first = await service.get(
      'https://vip.dytt-img.com/upload/vod/cover.webp',
    );
    expect(first.statusCode, 200);
    expect(requests.map((uri) => uri.host), ['vip.dytt-img.com', 'wsrv.nl']);

    requests.clear();
    final second = await service.get(
      'https://vip.dytt-img.com/upload/vod/other.webp',
    );
    expect(second.statusCode, 200);
    expect(requests.map((uri) => uri.host), ['wsrv.nl']);
  });

  test('直连与镜像都返回失败状态时保留最后的真实响应', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('', 404);
    });
    final service = serviceWith(client);

    final response = await service.get('https://dead.example/cover.jpg');
    expect(response.statusCode, 404);
    expect(
      requests.map((uri) => uri.host),
      ['dead.example', 'wsrv.nl'],
    );
  });

  test('镜像不可用的地址不会发起第二跳', () async {
    final requests = <Uri>[];
    final client = MockClient((request) async {
      requests.add(request.url);
      throw const SocketExceptionLike('connection reset');
    });
    final service = serviceWith(client);

    await expectLater(
      service.get('http://192.168.1.2/cover.jpg'),
      throwsA(isA<SocketExceptionLike>()),
    );
    expect(requests.map((uri) => uri.host), ['192.168.1.2']);
  });
}

/// 只用于测试的等价异常，避免依赖 dart:io 的具体异常类型。
class SocketExceptionLike implements Exception {
  const SocketExceptionLike(this.message);
  final String message;
  @override
  String toString() => 'SocketExceptionLike: $message';
}
