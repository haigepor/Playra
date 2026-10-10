import 'package:kazumi/services/platform/platform_io.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kazumi/services/platform/resource_url.dart';

import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/services/player/external_player.dart';

class ExternalPlaybackLauncher {
  final String Function() videoUrl;
  final String Function() referer;

  ExternalPlaybackLauncher({required this.videoUrl, required this.referer});

  Future<void> launch() async {
    final currentVideoUrl = videoUrl();
    final currentReferer = referer();
    if (kIsWeb) {
      final url = platformResourceUrl(
        currentVideoUrl,
        headers: {if (currentReferer.isNotEmpty) 'Referer': currentReferer},
      );
      if (!await launchUrl(Uri.parse(url), webOnlyWindowName: '_blank')) {
        KazumiDialog.showToast(message: '无法在浏览器中打开视频');
      }
      return;
    }
    if ((Platform.isAndroid || Platform.isWindows) && currentReferer.isEmpty) {
      if (await ExternalPlayer.launchUrlWithMime(
        currentVideoUrl,
        'video/mp4',
      )) {
        KazumiDialog.showToast(message: '尝试唤起外部播放器');
      } else {
        KazumiDialog.showToast(message: '唤起外部播放器失败');
      }
    } else if (Platform.isMacOS || Platform.isIOS) {
      if (await ExternalPlayer.launchUrlWithReferer(
        currentVideoUrl,
        currentReferer,
      )) {
        KazumiDialog.showToast(message: '尝试唤起外部播放器');
      } else {
        KazumiDialog.showToast(message: '唤起外部播放器失败');
      }
    } else if (Platform.isLinux && currentReferer.isEmpty) {
      final result = await ExternalPlayer.launchLinuxDesktopPlayer(
        currentVideoUrl,
      );
      switch (result) {
        case LinuxExternalPlayerResult.launched:
          KazumiDialog.showToast(message: '尝试唤起外部播放器');
        case LinuxExternalPlayerResult.cancelled:
          break;
        case LinuxExternalPlayerResult.unavailable:
          KazumiDialog.showToast(message: '系统应用选择器不可用');
        case LinuxExternalPlayerResult.failed:
          KazumiDialog.showToast(message: '唤起外部播放器失败');
      }
    } else {
      if (currentReferer.isEmpty) {
        KazumiDialog.showToast(message: '暂不支持该设备');
      } else {
        KazumiDialog.showToast(message: '暂不支持该规则');
      }
    }
  }
}
