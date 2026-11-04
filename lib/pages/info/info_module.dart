import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/player/player_controller.dart';
import 'package:kazumi/pages/source_unavailable_page.dart';
import 'package:kazumi/pages/video/video_controller.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/presentation/modern/pages/sdk_player_detail_page.dart';

final infoModule = createModule(
  path: '/info',
  register: (c) {
    c.route(
      '/',
      provide: (s) => s
        ..add<VideoPageController>(VideoPageController.new)
        ..add<PlayerController>(PlayerController.new),
      child: (context, state) {
        final entry = state.arguments;
        // 旧来源（bangumi 条目等非 SdkPlaybackEntry 参数）由类型检查挡下；
        // 所有 SdkPlaybackProvider（Lumina / 第二源）统一走 SdkDetailPage。
        if (entry is SdkPlaybackEntry) {
          return SdkDetailPage(entry: entry);
        }
        return const SourceUnavailablePage(feature: '旧来源作品详情');
      },
    );
  },
);
