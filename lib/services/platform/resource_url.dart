import 'dart:convert';
import 'package:flutter/foundation.dart';

/// 浏览器资源统一经同源网关加载，原生平台保持原始地址和请求头。
String platformResourceUrl(
  String url, {
  Map<String, dynamic> headers = const {},
}) {
  if (!kIsWeb || !['http', 'https'].contains(Uri.tryParse(url)?.scheme)) {
    return url;
  }
  return Uri.base
      .resolve('/api/proxy')
      .replace(
        queryParameters: {
          'url': url,
          if (headers.isNotEmpty)
            'headers': base64Url.encode(utf8.encode(jsonEncode(headers))),
        },
      )
      .toString();
}
