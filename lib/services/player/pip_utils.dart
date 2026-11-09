import 'package:kazumi/services/platform/platform_io.dart';

import 'package:flutter/services.dart';
import 'package:kazumi/services/logging/logger.dart';
import 'package:window_manager/window_manager.dart';

class PipUtils {
  static bool androidPIPInited = false;
  static Object? _handlerOwner;
  static Rect? _desktopBounds;
  static bool _desktopAlwaysOnTop = false;
  static bool _desktopMaximized = false;
  static bool _desktopFullscreen = false;
  static Future<void> _desktopRequest = Future.value();

  // 比例约分
  static Size getPIPAspectSize({required int width, required int height}) {
    if (width <= 0 || height <= 0) {
      return const Size(16, 9);
    }
    final int divisor = width.gcd(height);
    return Size(width / divisor, height / divisor);
  }

  static Future<bool> isAndroidPIPSupported() async {
    if (!Platform.isAndroid) {
      return false;
    }
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      final bool? supported = await pipChannel.invokeMethod(
        'isPictureInPictureSupported',
      );
      return supported ?? false;
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to check Android PIP support: '${e.message}'.");
      return false;
    }
  }

  static Future<bool> enterAndroidPIPWindow({
    int width = 16,
    int height = 9,
  }) async {
    if (!Platform.isAndroid) {
      return false;
    }
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      final bool? entered = await pipChannel.invokeMethod(
        'enterPictureInPictureMode',
        {
          'width': aspectSize.width.toInt(),
          'height': aspectSize.height.toInt(),
        },
      );
      return entered ?? false;
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to enter Android PIP mode: '${e.message}'.");
      return false;
    }
  }

  static Future<void> updateAndroidPIPActions({
    required bool playing,
    required bool danmakuEnabled,
    int width = 16,
    int height = 9,
    Rect? sourceRect,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }
    final Size aspectSize = getPIPAspectSize(width: width, height: height);
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      await pipChannel.invokeMethod('updatePictureInPictureActions', {
        'playing': playing,
        'danmakuEnabled': danmakuEnabled,
        'width': aspectSize.width.toInt(),
        'height': aspectSize.height.toInt(),
        if (sourceRect != null) ...{
          'sourceLeft': sourceRect.left.round(),
          'sourceTop': sourceRect.top.round(),
          'sourceRight': sourceRect.right.round(),
          'sourceBottom': sourceRect.bottom.round(),
        },
      });
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to update Android PIP actions: '${e.message}'.");
    }
  }

  static Future<void> setAndroidAutoEnterPIPEnabled(bool enabled) async {
    if (!Platform.isAndroid) {
      return;
    }
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      await pipChannel.invokeMethod('setAndroidAutoEnterPIPEnabled', {
        'enabled': enabled,
      });
    } on PlatformException catch (e) {
      KazumiLogger().e(
        "Failed to set Android auto-enter PIP enabled state: '${e.message}'.",
      );
    }
  }

  static Future<void> setAndroidPIPInPlayerPage(bool inPlayerPage) async {
    if (!Platform.isAndroid) {
      return;
    }
    const pipChannel = MethodChannel('com.predidit.kazumi/pip');
    try {
      await pipChannel.invokeMethod('setAndroidPIPInPlayerPage', {
        'inPlayerPage': inPlayerPage,
      });
    } on PlatformException catch (e) {
      KazumiLogger().e("Failed to set Android PIP page state: '${e.message}'.");
    }
  }

  // 进入桌面设备小窗模式，并用播放源比例固定窗口宽高比
  static Future<void> enterDesktopPIPWindow({int width = 16, int height = 9}) =>
      _queueDesktop(() async {
        if (_desktopBounds == null) {
          final size = await windowManager.getSize();
          final position = await windowManager.getPosition();
          _desktopAlwaysOnTop = await windowManager.isAlwaysOnTop();
          _desktopMaximized = await windowManager.isMaximized();
          _desktopFullscreen = await windowManager.isFullScreen();
          _desktopBounds = position & size;
          if (_desktopFullscreen) await windowManager.setFullScreen(false);
          if (_desktopMaximized) await windowManager.unmaximize();
        }
        final Size aspectSize = getPIPAspectSize(width: width, height: height);
        final double aspectRatio = aspectSize.width / aspectSize.height;
        const double pipWidth = 480;
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setAspectRatio(aspectRatio);
        await windowManager.setSize(Size(pipWidth, pipWidth / aspectRatio));
      });

  // 退出桌面设备小窗模式
  static Future<void> exitDesktopPIPWindow({bool restoreFullscreen = true}) => _queueDesktop(() async {
    final bounds = _desktopBounds;
    if (bounds == null) return;
    await windowManager.setAspectRatio(0);
    await windowManager.setSize(bounds.size);
    await windowManager.setPosition(bounds.topLeft);
    await windowManager.setAlwaysOnTop(_desktopAlwaysOnTop);
    if (_desktopMaximized) await windowManager.maximize();
    if (_desktopFullscreen && restoreFullscreen) await windowManager.setFullScreen(true);
    _desktopBounds = null;
  });

  static Future<void> _queueDesktop(Future<void> Function() operation) {
    final request = _desktopRequest.then((_) => operation());
    _desktopRequest = request.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return request;
  }

  static void initPipHandler({
    required Object owner,
    required Future<void> Function(String action) onAction,
    required void Function(bool inPipMode) onModeChanged,
  }) {
    const MethodChannel pipChannel = MethodChannel('com.predidit.kazumi/pip');
    _handlerOwner = owner;
    androidPIPInited = true;

    pipChannel.setMethodCallHandler((call) async {
      if (!identical(_handlerOwner, owner) || !Platform.isAndroid) {
        return;
      }

      final Object? args = call.arguments;
      final Map? arguments = (args is Map) ? args : null;

      switch (call.method) {
        case 'onModeChanged':
          final bool? inPipMode = arguments?['isInPipMode'] as bool?;
          if (inPipMode != null) {
            onModeChanged(inPipMode);
          }
        case 'onAction':
          final String? action = arguments?['action'] as String?;
          if (action != null) {
            await onAction(action);
          }
      }
    });
  }

  static void disposePipHandler(Object owner) {
    if (!identical(_handlerOwner, owner)) return;
    _handlerOwner = null;
    const MethodChannel pipChannel = MethodChannel('com.predidit.kazumi/pip');
    pipChannel.setMethodCallHandler(null);
    androidPIPInited = false;
  }
}
