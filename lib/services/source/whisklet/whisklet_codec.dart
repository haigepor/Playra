import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// 第二内容源（Whisklet）的构建期常量与请求头。
///
/// 上游地址可用 `--dart-define=WHISKLET_HOST/PORT/ENTRY` 覆盖；Android 明文
/// 放行清单是同包的 `provider_network_security.xml`，换址需同步。
class WhiskletProfile {
  static const host = String.fromEnvironment(
    'WHISKLET_HOST',
    defaultValue: '198.16.39.44',
  );
  static const port = int.fromEnvironment('WHISKLET_PORT', defaultValue: 27264);
  static const entry = String.fromEnvironment(
    'WHISKLET_ENTRY',
    defaultValue: '/nzjm.php/v7/logs',
  );

  static Uri get endpoint => Uri.http('$host:$port', entry);

  static const buildTime = '1789392128532';
  static final String packageId = utf8.decode(
    base64.decode('Y29tLmpqcGVuZ2NoZW5nLmNhbGxzaG93LnpqbWM='),
  );
  static final Uint8List key = Uint8List.fromList(
    md5
        .convert(
          utf8.encode(
            buildTime + utf8.decode(base64.decode('Xn4hQCNbLQ==')) + packageId,
          ),
        )
        .bytes,
  );
  static Map<String, String> get headers => {
    'user-agent': 'Dart/3.13 (dart:io)',
    'version': '4.0.6',
    'version-number': '106',
    'content-type': 'text/plain',
    'pk-id': packageId,
    'build-time': buildTime,
    'platform': 'android',
    'platform-version': 'android 9',
  };
}

/// 请求信封 = base64url(iv16 ‖ AES-128-CBC(PKCS7(json)))，去掉 `=` 填充。
/// 响应信封是三段 base64：头部长度表 / 加密体 / `xddappsecretkey<长度>` 尾，
/// 只有 app_config、video_detail、secret_parse_api_url 走该信封，其余接口
/// 直接返回 JSON。上游头部会周期变化，这里按尾部长度表还原并逐字节对齐
/// 尝试解密，不猜测缺失的影片字段。
class WhiskletCodec {
  WhiskletCodec({Uint8List? key}) : key = key ?? WhiskletProfile.key;
  final Uint8List key;

  static const configKeys = {
    'img_config',
    'advert_config',
    'modules_config',
    'find_config',
    'share_config',
    'contact_config',
    'comment_config',
    'short_config',
    'live_config',
    'dm_config',
    'history_config',
    'report_config',
    'video_detail_config',
    'player_config',
  };

  static Uint8List _decode(String value) =>
      base64.decode(base64.normalize(value));
  static String _encode(List<int> value) =>
      base64Url.encode(value).replaceAll('=', '');

  Uint8List _crypt(bool encrypting, Uint8List iv, Uint8List bytes) {
    final cipher = PaddedBlockCipherImpl(
      PKCS7Padding(),
      CBCBlockCipher(AESEngine()),
    );
    cipher.init(
      encrypting,
      PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
        ParametersWithIV(KeyParameter(key), iv),
        null,
      ),
    );
    return cipher.process(bytes);
  }

  String encrypt(Map<String, dynamic> value, {Uint8List? iv}) {
    final random = Random.secure();
    final vector =
        iv ?? Uint8List.fromList(List.generate(16, (_) => random.nextInt(256)));
    if (vector.length != 16) throw const FormatException('Invalid IV');
    return _encode([
      ...vector,
      ..._crypt(
        true,
        vector,
        Uint8List.fromList(utf8.encode(jsonEncode(value))),
      ),
    ]);
  }

  Map<String, dynamic> decryptRequest(String wire) {
    final bytes = _decode(wire);
    return _object(
      utf8.decode(_crypt(false, bytes.sublist(0, 16), bytes.sublist(16))),
    );
  }

  static Map<String, dynamic> _object(String text) {
    final value = jsonDecode(text);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected response object');
    }
    return value;
  }

  Map<String, dynamic> decode(String wire, String method) {
    final text = wire.trim();
    if (text.startsWith('{')) return _object(text);
    final marker = base64
        .encode(utf8.encode('xddappsecretkey'))
        .replaceAll('=', '');
    final tailAt = text.lastIndexOf(marker);
    if (tailAt < 0) throw const FormatException('Missing envelope');
    final tail = ascii.decode(_decode(text.substring(tailAt)));
    final match = RegExp(r'^xddappsecretkey(\d+)$').firstMatch(tail);
    if (match == null) throw const FormatException('Invalid envelope tail');
    final headLength = int.parse(match.group(1)!);
    if (headLength <= 0 || headLength > tailAt || headLength > 4096) {
      throw const FormatException('Invalid envelope length');
    }
    final head = ascii.decode(_decode(text.substring(0, headLength)));
    if (!RegExp(r'^(0x\d+)+$').hasMatch(head)) {
      throw const FormatException('Invalid envelope header');
    }
    final middle = _decode(text.substring(headLength, tailAt));
    if (method == 'vod_heat_add' && middle.length < 48) {
      return {
        'data': null,
        '_meta': {
          'mode': 'receipt',
          'reconstructed_header': true,
          'verified': false,
        },
      };
    }
    if (!{
      'app_config',
      'video_detail',
      'secret_parse_api_url',
    }.contains(method)) {
      throw const FormatException('Unexpected envelope method');
    }
    for (var skip = 0; skip < 16; skip++) {
      final length = middle.length - skip - 16;
      if (length < 32 || length % 16 != 0) continue;
      try {
        final body = utf8.decode(
          _crypt(
            false,
            middle.sublist(skip, skip + 16),
            middle.sublist(skip + 16),
          ),
        );
        if (!body.trimRight().endsWith('}')) continue;
        final recovered = _recover(body, method);
        recovered['_meta'] = {
          'mode': 'recovered',
          'reconstructed_header': true,
          'verified': false,
          'skip': skip,
        };
        return recovered;
      } on ArgumentError {
        continue;
      } on FormatException {
        continue;
      }
    }
    throw const FormatException('Cannot decode envelope');
  }

  Map<String, dynamic> _recover(String body, String method) {
    try {
      return _object(body);
    } on FormatException {
      // 仅补协议已知前缀；影片字段和解析字符串内容不凭空修复。
    }
    if (method == 'video_detail') {
      final anchor = body.indexOf('"vod_info":');
      if (anchor >= 0 && anchor < 96) {
        final value = _object('{"code":1,"data":{${body.substring(anchor)}');
        if ((value['data'] as Map?)?['vod_info'] is Map) return value;
      }
    }
    final templates = method == 'app_config'
        ? [
            r'{"code":1,"msg":"app\u914d\u7f6e","data":{"img_config":{"splash_img":""},"advert_config":{"adver',
          ]
        : method == 'video_detail'
        ? [r'{"code":1,"msg":"\u89c6\u9891\u8be6\u60c5","data":{"vod_info":{"']
        : ['{"code":1,"msg":"","data":"', '{"code":1,"data":"'];
    for (final template in templates) {
      for (
        var length = 0;
        length <= template.length && length <= 96;
        length++
      ) {
        try {
          final value = _object(template.substring(0, length) + body);
          if (value.containsKey('code') && value['code'] is! int) continue;
          if (method == 'app_config') {
            final data = value['data'];
            if (data is! Map ||
                data.length != configKeys.length ||
                !configKeys.containsAll(data.keys)) {
              continue;
            }
            if (data['img_config'] is! Map ||
                !(data['img_config'] as Map).containsKey('splash_img')) {
              continue;
            }
          } else if (method == 'video_detail') {
            if (value['data'] is! Map || value['data']['vod_info'] is! Map) {
              continue;
            }
          } else if (value['data'] is! String ||
              (value['data'] as String).length < 32) {
            continue;
          }
          return value;
        } on FormatException {
          continue;
        }
      }
    }
    throw const FormatException('Incomplete response payload');
  }
}

Map<String, dynamic> decodeWhiskletResponse((String, String) input) =>
    WhiskletCodec().decode(input.$1, input.$2);
