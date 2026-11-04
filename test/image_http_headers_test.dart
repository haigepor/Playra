import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/utils/image_extension.dart';

void main() {
  test('豆瓣系图床带 UA + Referer，其余域名不加头', () {
    final douban = httpHeadersForImageUrl(
      'https://img2.doubanio.com/view/photo/s_ratio_poster/public/p2936709341.jpg',
    );
    expect(douban, containsPair('Referer', 'https://www.douban.com/'));
    expect(douban['User-Agent'], startsWith('Mozilla/5.0'));

    expect(
      httpHeadersForImageUrl('https://www.douban.com/photos/photo/1'),
      isNotEmpty,
    );
    // 腾讯系 CDN 对带 Referer 的请求历史上回 404，必须保持无头。
    expect(
      httpHeadersForImageUrl(
        'https://vcover-vt-pic.puui.qpic.cn/vcover_vt_pic/0/mzc002000s9f77y1787036094007/0',
      ),
      isEmpty,
    );
    expect(
      httpHeadersForImageUrl('https://snzypic.com/upload/vod/1.jpg'),
      isEmpty,
    );
    expect(httpHeadersForImageUrl(''), isEmpty);
    expect(httpHeadersForImageUrl('::::not-a-url'), isEmpty);
    // 防误伤：长公共后缀不算豆瓣域。
    expect(
      httpHeadersForImageUrl('https://evil.example/doubanio.com/x.jpg'),
      isEmpty,
    );
  });
}
