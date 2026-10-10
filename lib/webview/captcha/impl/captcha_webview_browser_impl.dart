import 'dart:async';
import 'package:dio/dio.dart';
import 'package:kazumi/webview/captcha/captcha_webview_controller.dart';

/// 在受限的同源 Chromium 会话中执行规则已有的验证流程。
class CaptchaWebviewBrowserImpl extends CaptchaWebviewController {
  final _client = Dio();
  String? _id;
  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;
  Future<Map<String, dynamic>> _call(Map<String, dynamic> data) async {
    final response = await _client.post<Map<String, dynamic>>(
      Uri.base.resolve('/api/captcha').toString(),
      data: data,
      options: Options(
        headers: {'X-Kazumi-Request': '1'},
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    return response.data ?? {};
  }

  @override
  Future<void> init() async {
    initEventController.add(true);
  }

  Future<void> _open(Map<String, dynamic> data) async {
    await unloadPage();
    final response = await _call({'action': 'open', ...data});
    _id = response['id'] as String;
    if (_disposed) {
      await unloadPage();
      return;
    }
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => unawaited(_poll()),
    );
  }

  Future<void> _poll() async {
    final id = _id;
    if (id == null || _polling || _disposed) return;
    _polling = true;
    try {
      final response = await _call({'action': 'poll', 'id': id});
      if (_disposed || _id != id) return;
      final image = response['image'] as String?;
      if (image != null) captchaImageFoundController.add(image);
      if (response['done'] == true) {
        _timer?.cancel();
        captchaDisappearedController.add(null);
      }
    } catch (error) {
      if (!_disposed) {
        _timer?.cancel();
        logEventController.add('浏览器验证失败：$error');
      }
    } finally {
      _polling = false;
    }
  }

  @override
  Future<void> loadPage(
    String url,
    String captchaXpath, {
    String? inputXpath,
  }) => _open({
    'url': url,
    'mode': 'image',
    'captchaXpath': captchaXpath,
    'inputXpath': inputXpath,
  });
  @override
  Future<void> loadPageForButtonClick(String url, String buttonXpath) =>
      _open({'url': url, 'mode': 'button', 'buttonXpath': buttonXpath});
  @override
  Future<void> loadPageForCustomScript(String url, String script) =>
      _open({'url': url, 'mode': 'script', 'script': script});
  @override
  Future<void> submitCaptchaInteract(
    String captchaCode,
    String inputXpath,
    String buttonXpath,
  ) async {
    await _call({
      'action': 'submit',
      'id': _id,
      'code': captchaCode,
      'inputXpath': inputXpath,
      'buttonXpath': buttonXpath,
    });
  }

  Future<Map<String, dynamic>> _data() => _call({'action': 'data', 'id': _id});
  @override
  Future<String> getCookieString(String pageUrl) async =>
      (await _data())['cookie'] as String? ?? '';
  @override
  Future<String> getPageHtml() async =>
      (await _data())['html'] as String? ?? '';
  @override
  Future<String> getUserAgent() async =>
      (await _data())['userAgent'] as String? ?? '';
  @override
  Future<void> unloadPage() async {
    _timer?.cancel();
    _timer = null;
    final id = _id;
    _id = null;
    if (id != null) await _call({'action': 'close', 'id': id});
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(unloadPage().whenComplete(() => _client.close(force: true)));
    unawaited(captchaImageFoundController.close());
    unawaited(captchaDisappearedController.close());
    unawaited(initEventController.close());
    unawaited(logEventController.close());
  }
}
