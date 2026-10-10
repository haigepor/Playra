import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

void Function() listenBrowserFullscreen(void Function(bool) onChange) {
  final listener = ((web.Event event) {
    onChange(web.document.fullscreenElement != null);
  }).toJS;
  web.document.addEventListener('fullscreenchange', listener);
  return () => web.document.removeEventListener('fullscreenchange', listener);
}

Future<void> setBrowserFullscreen(bool value) async {
  if (value && web.document.fullscreenElement == null) {
    await web.document.documentElement!.requestFullscreen().toDart;
  } else if (!value && web.document.fullscreenElement != null) {
    await web.document.exitFullscreen().toDart;
  }
}

@JS('Object.getOwnPropertyNames')
external JSArray<JSString> _propertyNames(JSObject object);

// 与 media_kit_video 使用同一实例表，避免 Flutter 封闭的 Shadow DOM 阻止查找。
web.HTMLVideoElement? _video() {
  final instances = globalContext.getProperty<JSObject?>(
    r'$com.alexmercerind.media_kit.instances'.toJS,
  );
  if (instances == null) return null;
  for (final key in _propertyNames(instances).toDart.reversed) {
    if (int.tryParse(key.toDart) != null) {
      return instances.getProperty<web.HTMLVideoElement>(key);
    }
  }
  return null;
}

Future<bool> enterBrowserPictureInPicture() async {
  final video = _video();
  if (!web.document.pictureInPictureEnabled ||
      video == null ||
      video.readyState < 2)
    return false;
  try {
    await video.requestPictureInPicture().toDart;
    return true;
  } catch (_) {
    return false;
  }
}

void setBrowserVideoBrightness(double value) {
  final video = _video();
  // 浏览器不能修改显示器背光，调整视频画面亮度以保留手势行为。
  if (video != null)
    video.style.filter = 'brightness(${value.clamp(0.0, 1.0)})';
}
