import 'dart:math' as math;

import 'package:flutter/material.dart';

typedef VideoPlayerLayout = ({bool fillsWindow, bool hasSidePanel});

/// Fullscreen fills the available window; rotation belongs to the OS.
class VideoPageLayout extends StatelessWidget {
  const VideoPageLayout({
    super.key,
    required this.fullscreen,
    required this.isPip,
    required this.playerBuilder,
    required this.tabs,
    this.sidePanel,
    this.portraitFullscreen = false,
    this.portraitAspectRatio,
  });

  final bool fullscreen;
  final bool isPip;
  final Widget Function(BuildContext context, VideoPlayerLayout layout)
      playerBuilder;
  final Widget tabs;
  final Widget? sidePanel;

  /// Manual portrait fullscreen from the top bar; the normal fullscreen
  /// button keeps the existing landscape behaviour.
  final bool portraitFullscreen;
  final double? portraitAspectRatio;

  @override
  Widget build(BuildContext context) {
    if (portraitFullscreen) {
      return PortraitVideoCanvas(
        aspectRatio: portraitAspectRatio,
        child: playerBuilder(
          context,
          (fillsWindow: true, hasSidePanel: false),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final fillsWindow =
          fullscreen || isPip || constraints.maxWidth > constraints.maxHeight;
      final hasSidePanel = fillsWindow && !isPip && sidePanel != null;
      return SafeArea(
        top: !fillsWindow,
        bottom: !fillsWindow,
        left: !fillsWindow,
        right: !fillsWindow,
        child: Stack(
          alignment: Alignment.centerRight,
          children: [
            Column(
              children: [
                Flexible(
                  flex: fillsWindow ? 1 : 0,
                  child: SizedBox(
                    height: fillsWindow ? double.infinity : null,
                    width: double.infinity,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Builder(
                          builder: (context) => playerBuilder(context, (
                                fillsWindow: fillsWindow,
                                hasSidePanel: hasSidePanel
                              ))),
                    ),
                  ),
                ),
                if (!fillsWindow) Expanded(child: tabs),
              ],
            ),
            if (hasSidePanel) sidePanel!,
          ],
        ),
      );
    });
  }
}

/// A centred portrait canvas for manual portrait fullscreen.
///
/// The canvas fills the window height; on a landscape tablet it leaves black
/// side bars instead of stretching the 16:9 surface into a short band.
class PortraitVideoCanvas extends StatelessWidget {
  const PortraitVideoCanvas({
    super.key,
    required this.child,
    this.aspectRatio,
  });

  final Widget child;
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final aspect = aspectRatio ?? 9 / 16;
    final width = math.min(size.width, size.height * aspect);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: SizedBox(width: width, height: size.height, child: child),
      ),
    );
  }
}
