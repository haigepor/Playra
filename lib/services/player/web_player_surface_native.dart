import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// 编译边界：原生端继续使用 media_kit_video，不加载浏览器播放器。
class WebPlayerSurface extends StatelessWidget {
  const WebPlayerSurface({
    super.key,
    required this.controller,
    this.fit = BoxFit.contain,
    this.onNext,
    this.onDanmaku,
  });
  final VideoController controller;
  final BoxFit fit;
  final VoidCallback? onNext, onDanmaku;
  @override
  Widget build(BuildContext context) => Video(controller: controller, fit: fit);
}
