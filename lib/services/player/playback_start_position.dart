import 'package:media_kit/media_kit.dart';

/// 当前 Web HLS 引擎忽略 Media.start；元数据就绪后补定位，不影响原生起播。
Future<void> restorePlaybackStart(
  Player player,
  Duration start, {
  required bool Function() isCurrent,
  Duration budget = const Duration(seconds: 25),
}) async {
  if (start <= Duration.zero || !isCurrent()) return;
  try {
    var duration = player.state.duration;
    if (duration <= Duration.zero) {
      duration = await player.stream.duration
          .firstWhere((value) => value > Duration.zero)
          .timeout(budget);
    }
    // 退页、切线或超范围历史不能定位到新的媒体；不持久化任何新身份。
    if (isCurrent() && start < duration) await player.seek(start);
  } catch (_) {
    // 取消、关闭流和首帧超时由现有播放会话处理，不能产生未捕获的迟到异常。
  }
}
