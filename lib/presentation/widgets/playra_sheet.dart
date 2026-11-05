import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/playra_tokens.dart';
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

  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    routeSettings: routeSettings,
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
        final tokens = context.playraTokens;

        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: Padding(
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
                                    color: tokens.borderSubtle,
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
                                        color: tokens.foreground,
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
            ),
          ),
        );
      },
    ),
  );
}
