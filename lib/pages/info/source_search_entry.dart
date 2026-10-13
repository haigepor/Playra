import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/pages/video/video_playback_args.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';

/// 搜索页传递真实作品身份与当前来源集合，不修改用户安装列表。
class SourceSearchEntry {
  SourceSearchEntry({
    required this.item,
    required Iterable<Plugin> rules,
    this.playbackArgs,
  }) : rules = List.unmodifiable(rules);
  final BangumiItem item;
  final List<Plugin> rules;
  final OnlineVideoPlaybackArgs? playbackArgs;
}

class MioSearchEntry {
  const MioSearchEntry(this.item);
  final MioVideo item;
}
