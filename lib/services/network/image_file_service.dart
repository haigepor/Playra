import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:kazumi/services/logging/logger.dart';
import 'package:kazumi/services/network/bangumi_ech_image_service.dart';
import 'package:kazumi/services/network/bangumi_image_url_rewriter.dart';
import 'package:kazumi/services/network/image_acceleration.dart';
import 'package:kazumi/services/network/image_file_response.dart';
import 'package:kazumi/services/network/image_mirror.dart';

/// 图片请求按 ECH / 直连 / 镜像逐级回退。
///
/// 片源图床经常出现单点不可达：域名被污染、被本地网络阻断或源站拒绝，
/// 而同一张图经公共镜像仍可取得。逐级回退只发生在失败之后，正常直连的
/// 延迟与请求头行为不变；镜像成功过的主机在当前会话内优先走镜像，
/// 避免每次滚动都先等一次直连失败。
class ImageFileService extends FileService {
  ImageFileService({
    required ImageAcceleration Function() acceleration,
    required http.Client Function() clientFactory,
    required BangumiEchImageService echService,
  }) : _acceleration = acceleration,
       _clientFactory = clientFactory,
       _echService = echService;

  /// 单次尝试（含连接与响应头）的上限；超时后换下一条链路。
  static const _attemptTimeout = Duration(seconds: 12);

  final ImageAcceleration Function() _acceleration;
  final http.Client Function() _clientFactory;
  final BangumiEchImageService _echService;
  final _clients = <http.Client>{};
  final _mirrorPreferredHosts = <String>{};
  bool _closed = false;

  void resetNetworkClients() {
    _echService.reset();
    // 网络环境变化后重新给直连一次机会。
    _mirrorPreferredHosts.clear();
  }

  void close() {
    _closed = true;
    _echService.close();
    for (final client in _clients) {
      client.close();
    }
    _clients.clear();
  }

  @override
  Future<FileServiceResponse> get(
    String url, {
    Map<String, String>? headers,
  }) async {
    if (_closed) throw StateError('Image file service is closed');
    final original = Uri.parse(url);
    final mode = _acceleration();
    final useEch =
        mode == ImageAcceleration.ech &&
        BangumiImageUrlRewriter.isBangumiImage(original);
    final directUri = mode == ImageAcceleration.mirror
        ? BangumiImageUrlRewriter.rewrite(original)
        : original;
    final mirrorable = ImageMirror.canMirror(directUri);
    final mirrorFirst =
        mirrorable && _mirrorPreferredHosts.contains(original.host);

    final sources = <_ImageSource>[
      if (mirrorFirst) _ImageSource.mirror,
      if (useEch) _ImageSource.ech,
      _ImageSource.direct,
      if (mirrorable && !mirrorFirst) _ImageSource.mirror,
    ];

    FileServiceResponse? lastResponse;
    Object? lastError;
    for (final source in sources) {
      try {
        final response = switch (source) {
          _ImageSource.ech => await _echService
              .get(
                original.replace(scheme: 'https').toString(),
                headers: headers,
              )
              .timeout(_attemptTimeout),
          _ImageSource.direct => await _fetch(directUri, headers),
          _ImageSource.mirror => await _fetch(
            ImageMirror.rewrite(directUri),
            null,
          ),
        };
        if (_isUsable(response.statusCode)) {
          if (source == _ImageSource.mirror) {
            if (_mirrorPreferredHosts.add(original.host)) {
              KazumiLogger().w(
                'NetworkImage: 图片直连失败，已切换到镜像获取',
                error: original.host,
              );
            }
          } else {
            _mirrorPreferredHosts.remove(original.host);
          }
          return response;
        }
        lastResponse = response;
        await _discard(response);
      } catch (error) {
        lastError = error;
      }
    }
    // 返回最后一次真实响应，让 CacheManager 按状态码记录失败；
    // 全部为异常时抛出最后一个，保留原始错误。
    if (lastResponse != null) return lastResponse;
    throw lastError ?? const ImageFetchFailure();
  }

  Future<FileServiceResponse> _fetch(
    Uri uri,
    Map<String, String>? headers,
  ) async {
    final client = _clientFactory();
    _clients.add(client);
    try {
      final request = http.Request('GET', uri);
      if (headers != null) request.headers.addAll(headers);
      final response = await client.send(request).timeout(_attemptTimeout);
      return await createImageFileResponse(
        response,
        contentLength: response.contentLength,
        onComplete: () => _release(client),
      );
    } catch (_) {
      _release(client);
      rethrow;
    }
  }

  void _release(http.Client client) {
    if (_clients.remove(client)) client.close();
  }

  static bool _isUsable(int statusCode) =>
      statusCode == 200 || statusCode == 202 || statusCode == 304;

  static Future<void> _discard(FileServiceResponse response) async {
    try {
      await response.content.listen(null).cancel();
    } catch (_) {
      // 已经释放或流本身出错时无需再处理，继续下一条链路。
    }
  }
}

enum _ImageSource { ech, direct, mirror }

class ImageFetchFailure implements Exception {
  const ImageFetchFailure();

  @override
  String toString() => 'IMAGE_FETCH_FAILED: direct and mirror attempts failed';
}
