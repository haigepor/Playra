import 'package:flutter/material.dart';
import 'package:kazumi/features/sources/core/media_models.dart';
import 'package:kazumi/features/sources/sources.dart';
import 'package:kazumi/pages/discover/media_widgets.dart';
import 'package:kazumi/pages/player/source_player_page.dart';
import 'package:kazumi/pages/route_args.dart';
import 'package:kazumi/services/storage/storage.dart';

class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({super.key, required this.mediaKey});
  final MediaKey mediaKey;
  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  late Future<MediaDetail> _detail = _load();
  Future<MediaDetail> _load() async => mediaSources
      .byId(widget.mediaKey.sourceId)
      .loadDetail(widget.mediaKey.mediaId);

  @override
  Widget build(BuildContext context) => FutureBuilder<MediaDetail>(
    future: _detail,
    builder: (context, snapshot) {
      final detail = snapshot.data;
      if (detail == null) {
        return Scaffold(
          appBar: AppBar(),
          body: SafeArea(
            top: false,
            child: snapshot.hasError
                ? MediaStateScrollView(
                    child: MediaRetryNotice(
                      retrying:
                          snapshot.connectionState == ConnectionState.waiting,
                      message: '作品加载失败',
                      error: snapshot.error,
                      onRetry: () => setState(() {
                        _detail = _load();
                      }),
                    ),
                  )
                : const MediaLoadingState(label: '正在加载作品'),
          ),
        );
      }
      final history = HistoryStorage.get(
        detail.key.sourceId,
        detail.key.mediaId,
      );
      final savedRoad = history == null
          ? null
          : detail.roadByCode(history.roadCode);
      final canResume =
          history != null &&
          savedRoad != null &&
          !savedRoad.vipOnly &&
          savedRoad.episodes.any(
            (e) => !e.vipOnly && e.number == history.episode,
          );
      final road = canResume
          ? savedRoad
          : detail.roads
                    .where(
                      (r) => !r.vipOnly && r.episodes.any((e) => !e.vipOnly),
                    )
                    .firstOrNull ??
                detail.defaultRoad;
      final episode = canResume
          ? history.episode
          : road?.episodes.where((e) => !e.vipOnly).firstOrNull?.number ??
                road?.episodes.firstOrNull?.number ??
                0;
      return SourcePlayerPage(
        request: PlaybackRequest(
          sourceId: detail.key.sourceId,
          detail: detail,
          roadCode: road?.code ?? '',
          episode: episode,
        ),
      );
    },
  );
}
