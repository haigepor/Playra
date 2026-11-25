import 'package:kazumi/services/platform/platform_io.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:kazumi/services/player/screenshot_candidate.dart';
import 'package:path/path.dart' as path;
import 'package:saver_gallery/saver_gallery.dart';

class ScreenshotExportService {
  const ScreenshotExportService();

  static const _intentChannel = MethodChannel('com.predidit.kazumi/intent');
  static const _storageChannel = MethodChannel(
    'com.predidit.kazumi/download_directory',
  );

  Future<void> _ensureAndroidGalleryAccess() async {
    int? sdk;
    try {
      sdk = await _intentChannel.invokeMethod<int>('getAndroidSdkVersion');
    } catch (_) {
      throw StateError('无法获取 Android 系统版本，请重试');
    }
    if (sdk == null || sdk <= 0) {
      throw StateError('无法获取 Android 系统版本，请重试');
    }
    if (sdk >= 29) return;

    bool? granted;
    try {
      granted = await _storageChannel.invokeMethod<bool>(
        'requestStorageAccess',
      );
    } catch (_) {
      throw StateError('无法请求存储权限，请重试');
    }
    if (granted != true) {
      throw StateError('未授予存储权限，请授权后重试');
    }
  }

  bool get _mobile =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<String?> chooseDestination() async {
    // Request once per batch; asking inside write() could re-prompt once for
    // every selected image after a denial.
    if (_mobile && defaultTargetPlatform == TargetPlatform.android) {
      await _ensureAndroidGalleryAccess();
    }
    if (kIsWeb || _mobile) return '/kazumi/screenshots';
    return FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择截图保存文件夹',
      lockParentWindow: true,
    );
  }

  Future<void> write(ScreenshotCandidate item, String location) async {
    final name = _fileName(item);
    if (kIsWeb) {
      await FilePicker.platform.saveFile(
        fileName: name,
        bytes: item.bytes,
        type: FileType.custom,
        allowedExtensions: const ['png'],
      );
      return;
    }
    if (_mobile) {
      final result = await SaverGallery.saveImage(
        item.bytes,
        fileName: name,
        extension: 'png',
        skipIfExists: false,
      );
      if (!result.isSuccess) {
        throw StateError(result.errorMessage ?? '保存到相册失败');
      }
      return;
    }
    var file = File(path.join(location, name));
    var suffix = 1;
    while (await file.exists()) {
      file = File(
        path.join(
          location,
          '${path.basenameWithoutExtension(name)}_${suffix++}.png',
        ),
      );
    }
    await file.writeAsBytes(item.bytes, flush: true);
  }

  static String _fileName(ScreenshotCandidate item) {
    String clean(String value) {
      final safe = value
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '_')
          .trim()
          .replaceAll(RegExp(r'[. ]+$'), '');
      // Leave room for the ID within common 255-byte filename limits.
      return String.fromCharCodes(safe.runes.take(24));
    }

    return 'Playra_${clean(item.title)}_${clean(item.episode)}_'
        '${item.timeLabel.replaceAll(':', '-')}_${item.id}.png';
  }
}
