// 红果签名栈固定向量（对标 openhongguo sign_test.go；金标准来自参考实现）。
// 本机 flutter test 受原生资产工具链阻塞时，可用
// `dart run tool/hongguo_sign_check.dart` 得到同一组断言的纯 Dart 裁决。
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/hongguo/hongguo_sign.dart';

String md5Hex(List<int> bytes) => crypto.md5
    .convert(bytes)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

void main() {
  test('sm3("abc") matches the published GM/T vector', () {
    final sum = sm3Sum(utf8.encode('abc'));
    expect(hexEncode(sum),
        '66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0');
  });

  test('xGorgon matches the reference implementation', () {
    const query = 'iid=7100000000000012&device_id=7100000000000011&ac=wifi'
        '&channel=update_64&aid=8662&app_name=novelread&version_code=71332'
        '&version_name=7.1.3.32&device_platform=android&os=android&ssmix=a'
        '&device_type=25053RT47C&device_brand=Redmi&language=zh&os_api=36'
        '&os_version=16&manifest_version_code=71332&resolution=1280*2772'
        '&dpi=520&update_version_code=71332&host_abi=arm64-v8a'
        '&dragon_device_type=phone&pv_player=71332&compliance_status=0'
        '&need_personal_recommend=1&player_so_load=1&is_android_pad_screen=0'
        '&ts=1700000000&_rticket=1700000000123';
    expect(
      xGorgon(query, utf8.encode('{"a":1}'), true, 1700000000, 0x1234),
      '84043412400154ed198c3230d5ff1364e71df6105a46126993c0',
    );
  });

  test('assembleHelios matches the reference implementation', () {
    expect(
      assembleHelios(1700000000, 2028160147),
      'k0TjeBWFFnRXfkeKlh3Hmx1jLjrfhgCasqsF4XvB1+0eB1Mw',
    );
  });

  test('medusa keyHash / xmxor / full header match the reference', () {
    final signKey = utf8.encode(
      String.fromCharCodes(_hexToBytes(
        '8ebdfa3806ecc5cee79423e6029ed82540bc2218bb7eaef71cb691f7aa8aa2f5',
      )),
    );
    final (hash, seed) = keyHash(signKey, 2378451149);
    expect(hexEncode(hash),
        '1b35023431b99a949ab7b70fc50a30216076492a6229d102a7a33fa3a1104170');
    expect(hexEncode(seed), 'b0dff9ff');
    expect(
      hexEncode(xmxor(utf8.encode('0123456789abcdefghij'), hash)),
      '5c69c37694106e8cbdb2e074619a1dda6c5a5a65',
    );
    const medusaWant =
        'A/FTZfcZDJ/XJo9e1tubFVc+Mn3NSAABthXCoU+OAdYPONbwm9+RyUZ1cbOs05Yl1aeIPCOGtW+GK2b4gMoFqK69oa1CtJNpHvFQ90KOznW75N3Iac3SIC2SIL/AEUa1LqRKHJc0OVAOzCUSF1PpwjNvKQMxteguS4MtQqRWQiRv25xZVCxPuR4K155Yu2XGsfoblNT6sUx3M9mDqh8WhMpoRbPjSwAij42sVoYMhYUMcyYL73j0agwgsSu/bMNgpLXppp9Hd7KwpiRPFCyDMGP892DPSagFV+ndwVa0M9GGxB3ksAgAUUr91XV5uEUA6/MJpv7AUUEpFfk101bKFHLmflVjL4B9K4OEos6OgkIx2gloIAOULcEBroYDODhlyRqqKT7TX53G09xaFF/YpqtuOC6ZkfG6MOBtYCrCeqgLtoubTaE/xh0VOVRVS/mQWvXYhS00Tqcb/ywQaQzDm1eBAxc1SgDLnzwzLAPLrmDI4rDLqaAWcL6yhsqXydzBShsdZOwreQE9pHzhm3Kaw1ZdV/FLHMqIKnuGoGOOAv19acvxPext43+ckznl5fV5pIj1txHIxcgg8/fQMx0xYM9ubLBnL3lZr+x7226u1kUngjM/IFDSCsVcs3QRzyjAGo+2SWLa8Sicyiq1QsQB5Xw0KWMNlA7lA8dRmxrs2ANytt9GeELT6TZqAWwwoCRbae6aXm+j2qgybmCrmffHBE3gZWgQ8pTjpWWRedesWrwwfioLmyWqRmZRl9TgaWiJpFQZwLFz9WnDhbk8/rFeQjtPH+/my02pcdEXl2Onwwg7/iS5nhWwmKn/k378VIdufE0rFeIAKs9npH8SwAuxaT0GEiWv0AZuXppB6clslZlunKcJHHZK2g/UtbSWEodVLcYPhnFt7cZe46GeFxdSUxNb26BpkjTtwLQGqVFFlFqGb5ijjxz6BVEBpXbZVpLW0+OKFDlfKj166UTiQdk4GfWp28mwvGYFiVqlBOew//nfsP/4n8SN';
    final medusa = assembleMedusa(
      'https://api5-normal-sinfonlineb.fqnovel.com/x/v1?aid=8662&device_id=7100000000000011&ts=1700000000',
      utf8.encode('{"a":1}'),
      true,
      1700000000,
      '7100000000000011',
      '7.1.3.32',
      HongguoEntropy(
        envLaunch: 103,
        envPID: 11691,
        nowSecs: 1700000000,
        messageRandom: 1273073252,
        random: 2378451149,
        packedRandom: 2253366658,
      ),
    );
    expect(medusa, medusaWant);
  });

  test('SignPOST covers the body; GET has no stub and differs', () {
    final ent = HongguoEntropy(
      nowSecs: 1700000000,
      gorgonRandom: 0x1234,
      heliosRandom: 1,
      messageRandom: 1,
      random: 1,
      packedRandom: 1,
      envLaunch: 100,
      envPID: 10001,
    );
    final body = utf8.encode('{"series_id":"1"}');
    final (query, post) = hongguoSignRequest(
      '/novel/player/video_detail/v1/',
      [('aid', '8662')],
      1700000000123,
      '1',
      '7.3.9.32',
      body,
      ent,
    );
    expect(query.query, contains('aid=8662'));
    expect(query.query, contains('ts='));
    expect(post['x-ss-stub'], md5Hex(body).toUpperCase());
    final (_, get) = hongguoSignRequest(
      '/novel/player/video_detail/v1/',
      [('aid', '8662')],
      1700000000123,
      '1',
      '7.3.9.32',
      null,
      ent,
    );
    expect(get['x-gorgon'], isNot(post['x-gorgon']));
    expect(get['x-ss-stub'], isNull);
  });
}

List<int> _hexToBytes(String hex) {
  final out = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
