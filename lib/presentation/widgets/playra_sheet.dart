import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' as f;

import '../theme/playra_tokens.dart';
import '../theme/playra_forui_theme.dart';
import 'playra_card.dart';
import 'playra_controls.dart';

enum PlayraSheetSize { action, standard, catalog }

/// Non-player sheets share a surface and motion, with widths chosen by purpose.
Future<T?> showPlayraSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  PlayraSheetSize size = PlayraSheetSize.action,
  String? title,
  bool useRootNavigator = true,
  bool showDragHandle = true,
  double maxHeightFactor = .8,
  RouteSettings? routeSettings,
}) {
  final viewport = MediaQuery.sizeOf(context);
  final target = switch (size) {
    PlayraSheetSize.action => PlayraLayout.actionSheetWidth,
    PlayraSheetSize.standard => PlayraLayout.sheetWidth,
    PlayraSheetSize.catalog => PlayraLayout.catalogWidth,
  };
  final width = viewport.width < PlayraLayout.compactWidth
      ? viewport.width
      : math.min(viewport.width - PlayraSpace.section, target);
  final navigator = Navigator.of(context, rootNavigator: useRootNavigator);
  final captured = f.FTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(
    f.FModalSheetRoute<T>(
      capturedFTheme: f.FCapturedTheme(
        theme:
            captured.theme ??
            AlwaysStoppedAnimation(playraForuiTheme(Theme.of(context))),
        accessibility: captured.accessibility,
        platform: captured.platform,
      ),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      settings: routeSettings,
      side: f.FLayout.btt,
      mainAxisMaxRatio: 1,
      resizeToAvoidBottomInset: false,
      useSafeArea: true,
      constraints: BoxConstraints(maxWidth: width),
      style: f.FModalSheetStyle(
        barrierFilter: f.FModalSheetStyle.defaultBarrierFilter,
        motion: f.FModalSheetMotion(
          expandDuration: PlayraMotion.duration(
            context,
            PlayraMotion.sheetEnter,
          ),
          collapseDuration: PlayraMotion.duration(
            context,
            PlayraMotion.sheetExit,
          ),
          curve: PlayraMotion.curve,
        ),
      ),
      builder: (context) => LayoutBuilder(
        builder: (context, bounds) {
          final media = MediaQuery.of(context);
          final keyboard = media.viewInsets.bottom;
          final shortLandscape =
              media.size.width > media.size.height &&
              media.size.height < PlayraLayout.compactWidth;
          final factor = keyboard > 0
              ? 1.0
              : shortLandscape
              ? math.max(.9, maxHeightFactor)
              : maxHeightFactor;
          final maxHeight = math.max(0.0, bounds.maxHeight - keyboard) * factor;
          final theme = Theme.of(context);
          return Padding(
            padding: EdgeInsets.only(bottom: keyboard),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: PlayraCard(
                kind: PlayraCardKind.hero,
                padding: EdgeInsets.zero,
                child: Theme(
                  data: theme.copyWith(
                    scaffoldBackgroundColor: Colors.transparent,
                  ),
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (showDragHandle)
                          ExcludeSemantics(
                            child: Center(
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                  vertical: PlayraSpace.md,
                                ),
                                width: PlayraSpace.section,
                                height: PlayraSpace.xs,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: .5),
                                  borderRadius: BorderRadius.circular(
                                    PlayraSpace.xs,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (title != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: PlayraSpace.xl,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    title,
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontSize: PlayraType.section,
                                    ),
                                  ),
                                ),
                                PlayraIconButton(
                                  tooltip: '关闭',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                          ),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Builder(builder: builder),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
