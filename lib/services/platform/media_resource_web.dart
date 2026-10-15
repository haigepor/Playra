import 'dart:js_interop';
import 'dart:convert';
import 'package:web/web.dart' as web;
import 'browser_file_system.dart';
import 'resource_url.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

final _dependencies = <String, List<String>>{};

@JS('PlayraMediaCompatibility.preferMseHls')
external JSBoolean _preferMseHls(int handle);

/// 复用 media_kit 的 HLS 引擎，避免 Chromium 原生探测与实际解码能力不一致。
Future<void> configureMediaPlayback(Player player) async {
  // handle 可先于 HLS 脚本就绪；等待播放器初始化，避免首次起播漏掉兼容设置。
  await player.platform?.waitForPlayerInitialization;
  _preferMseHls(await player.handle);
}

Future<String> prepareMediaResource(
  String url,
  Map<String, String> headers,
) async {
  if (url.startsWith('file:') || url.startsWith('/kazumi/')) {
    final path = url.startsWith('file:') ? Uri.parse(url).path : url;
    return _localResource(path, headers, <String>{});
  }
  return platformResourceUrl(url, headers: headers);
}

Future<String> _localResource(
  String path,
  Map<String, String> headers,
  Set<String> visiting,
) async {
  if (!visiting.add(path) || visiting.length > 4096) {
    throw StateError('本地播放列表循环或过大');
  }
  var bytes = await File(path).readAsBytes();
  final children = <String>[];
  final hls = path.toLowerCase().endsWith('.m3u8');
  try {
    if (hls) {
      Future<String> resolve(String value) async {
        if (['http', 'https'].contains(Uri.tryParse(value)?.scheme)) {
          return platformResourceUrl(value, headers: headers);
        }
        final childPath = value.startsWith('file:')
            ? Uri.parse(value).path
            : p.posix.normalize(p.posix.join(p.posix.dirname(path), value));
        final child = await _localResource(childPath, headers, visiting);
        children.add(child);
        return child;
      }

      final lines = <String>[];
      for (final line in utf8.decode(bytes).split('\n')) {
        if (line.trim().isNotEmpty && !line.startsWith('#')) {
          lines.add(await resolve(line.trim()));
        } else {
          final match = RegExp('URI="([^"]+)"').firstMatch(line);
          lines.add(
            match == null
                ? line
                : line.replaceRange(
                    match.start,
                    match.end,
                    'URI="${await resolve(match[1]!)}"',
                  ),
          );
        }
      }
      bytes = utf8.encode(lines.join('\n'));
    }
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(
        type: hls
            ? 'application/vnd.apple.mpegurl'
            : 'application/octet-stream',
      ),
    );
    // media-kit 根据地址识别 HLS；URL fragment 不会改变 Blob 的读取内容。
    final resource =
        '${web.URL.createObjectURL(blob)}${hls ? '#local.m3u8' : ''}';
    _dependencies[resource] = children;
    return resource;
  } catch (_) {
    for (final child in children) {
      releaseMediaResource(child);
    }
    rethrow;
  } finally {
    visiting.remove(path);
  }
}

void releaseMediaResource(String url) {
  for (final child in _dependencies.remove(url) ?? const <String>[]) {
    releaseMediaResource(child);
  }
  if (url.startsWith('blob:')) {
    web.URL.revokeObjectURL(Uri.parse(url).replace(fragment: '').toString());
  }
}
