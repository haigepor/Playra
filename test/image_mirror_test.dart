import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/network/image_mirror.dart';

void main() {
  test('普通图片地址改写为 wsrv 镜像并保留路径', () {
    final mirror = ImageMirror.rewrite(
      Uri.parse(
        'https://vip.dytt-img.com/upload/vod/20260504-1/cover.webp',
      ),
    );
    expect(mirror.host, 'wsrv.nl');
    expect(
      mirror.toString(),
      'https://wsrv.nl/?url=vip.dytt-img.com%2Fupload%2Fvod%2F20260504-1%2Fcover.webp',
    );
  });

  test('查询串原样进入镜像参数', () {
    final mirror = ImageMirror.rewrite(
      Uri.parse('https://img.example/cover.jpg?w=300&h=450'),
    );
    expect(
      mirror.toString(),
      'https://wsrv.nl/?url=img.example%2Fcover.jpg%3Fw%3D300%26h%3D450',
    );
  });

  test('GIF 关闭镜像的单帧优化', () {
    final mirror = ImageMirror.rewrite(
      Uri.parse('https://img.example/animated.gif'),
    );
    expect(mirror.queryParameters['n'], '-1');
  });

  test('镜像自身、内网地址和非 HTTP 协议不做二次镜像', () {
    expect(ImageMirror.canMirror(Uri.parse('https://wsrv.nl/?url=x')), isFalse);
    expect(
      ImageMirror.canMirror(Uri.parse('http://192.168.1.2/cover.jpg')),
      isFalse,
    );
    expect(
      ImageMirror.canMirror(Uri.parse('http://127.0.0.1:8080/cover.jpg')),
      isFalse,
    );
    expect(ImageMirror.canMirror(Uri.parse('http://localhost/a.jpg')), isFalse);
    expect(ImageMirror.canMirror(Uri.parse('file:///tmp/a.jpg')), isFalse);
    expect(
      ImageMirror.canMirror(Uri.parse('https://img.example/a.jpg')),
      isTrue,
    );
  });
}
