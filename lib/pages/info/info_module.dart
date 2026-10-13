import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/info/info_controller.dart';
import 'package:kazumi/pages/info/info_page.dart';
import 'package:kazumi/pages/route_error_page.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/pages/history/history_controller.dart';
import 'package:kazumi/pages/download/download_controller.dart';
import 'package:kazumi/presentation/interface_page_host.dart';
import 'package:kazumi/presentation/modern/pages/modern_player_detail_page.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_detail_page.dart';
import 'source_search_entry.dart';
import 'package:kazumi/pages/video/video_page.dart';

final infoModule = createModule(
  path: '/info',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s
        ..add<InfoController>(InfoController.new)
        ..add<VideoPageController>(VideoPageController.new)
        ..add<PlayerController>(PlayerController.new),
      child: (context, state) {
        final entry = state.arguments;
        if (entry is MioSearchEntry) {
          return MioDetailPage(item: entry.item, autoPlay: true);
        }
        final bangumiItem = entry is SourceSearchEntry ? entry.item : entry;
        if (bangumiItem is MioVideo) {
          return MioDetailPage(item: bangumiItem);
        }
        if (bangumiItem is! BangumiItem) {
          return const RouteErrorPage(message: '番组详情参数无效，请返回后重新打开。');
        }
        return InterfacePageHost(
          legacy: (_) =>
              entry is SourceSearchEntry && entry.playbackArgs != null
              ? VideoPage(
                  args: entry.playbackArgs!,
                  playerController: context.read<PlayerController>(),
                  videoPageController: context.read<VideoPageController>(),
                  historyController: inject<HistoryController>(),
                  downloadController: inject<DownloadController>(),
                )
              : InfoPage(
                  inputBangumiItem: bangumiItem,
                  infoController: context.read<InfoController>(),
                  sourceRules: entry is SourceSearchEntry ? entry.rules : null,
                ),
          modern: (_) => ModernPlayerDetailPage(
            args: entry is SourceSearchEntry ? entry.playbackArgs : null,
            item: bangumiItem,
            infoController: context.read<InfoController>(),
            videoController: context.read<VideoPageController>(),
            playerController: context.read<PlayerController>(),
            historyController: inject<HistoryController>(),
            downloadController: inject<DownloadController>(),
            sourceRules: entry is SourceSearchEntry ? entry.rules : null,
          ),
        );
      },
    );
  },
);
