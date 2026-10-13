import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/content_source_controller.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/player/source_media_player.dart';
import 'package:kazumi/services/player/web_player_surface.dart';
import '../home/home_theme.dart';

/// 使用来源引用直接播放；不伪造 BangumiItem、历史或账号身份。
class ContentWorkPage extends StatefulWidget {
  const ContentWorkPage({super.key, required this.work, required this.session});
  final ContentWork work;
  final ContentSearchSession session;
  @override
  State<ContentWorkPage> createState() => _ContentWorkPageState();
}

class _ContentWorkPageState extends State<ContentWorkPage> {
  late final sources = ContentSourceController(widget.session.providers);
  late final matchingSearch = ContentSearchSession(
    widget.session.providers,
    ownsProviders: false,
  );
  final media = SourceMediaPlayer();
  CancelToken? _play;
  Future<void> _mediaTail = Future.value();
  bool busy = false, _closed = false, _metadataLoading = false;
  String? message;
  @override
  void initState() {
    super.initState();
    _sync();
    widget.session.addListener(_sync);
    matchingSearch.addListener(_sync);
  }

  void _sync() {
    for (final hit in widget.work.hits) {
      sources.add(hit);
    }
    for (final work in matchingSearch.works) {
      for (final hit in work.hits) {
        if (widget.work.accepts(hit)) sources.add(hit);
      }
    }
  }

  Future<void> _select(ContentSourceBinding binding, ContentLine line) async {
    _play?.cancel('selection changed');
    setState(() {
      busy = false;
      message = '已选择线路，点击剧集播放';
    });
    await media.player?.pause();
    await sources.select(binding, line);
  }

  Future<void> _playEpisode(ContentEpisode episode) async {
    final binding = sources.selected, line = sources.selectedLine;
    if (binding == null || line == null) return;
    _play?.cancel('replaced');
    final cancel = _play = CancelToken();
    bool current() =>
        mounted && !_closed && !cancel.isCancelled && identical(_play, cancel);
    setState(() {
      busy = true;
      message = '正在解析所选来源…';
    });
    try {
      final material = await sources
          .provider(binding.hit)
          .resolve(binding.hit, line, episode, cancel);
      if (!current()) return;
      final previous = _mediaTail, done = Completer<void>();
      _mediaTail = done.future;
      try {
        await previous;
        if (!current()) return;
        final player = await media.open(
          material.url,
          material.headers,
          canInstall: current,
          onError: (_) {
            if (current()) setState(() => message = '媒体加载失败，请重试或选择其他来源');
          },
        );
        if (player == null || !current()) return;
        setState(() => message = '播放材料已取得，等待首帧…');
        final watch = Stopwatch()..start();
        while (current() && watch.elapsed < const Duration(seconds: 25)) {
          if (player.state.playlist.medias.any(
                (m) => m.uri == media.mediaUrl,
              ) &&
              (player.state.width ?? 0) > 0 &&
              (player.state.height ?? 0) > 0 &&
              player.state.position > const Duration(milliseconds: 200)) {
            setState(
              () => message =
                  '${sources.provider(binding.hit).name} · ${episode.title} · 已起播',
            );
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (current()) {
          setState(
            () => message = !player.state.playing
                ? '点击播放器继续；尚未确认起播'
                : '等待首帧超时，可重试或选择其他来源',
          );
        }
      } finally {
        done.complete();
      }
    } catch (error) {
      if (current()) {
        setState(
          () => message = error is SourceException
              ? '${error.message}（${error.code}）'
              : '播放未完成，请重试或选择其他来源',
        );
      }
    } finally {
      if (current()) setState(() => busy = false);
    }
  }

  Future<void> _metadata(ContentHit hit) async {
    if (_metadataLoading) return;
    setState(() => _metadataLoading = true);
    try {
      final id = int.tryParse(hit.contentId);
      final item = id == null ? null : await BangumiApi.getBangumiInfoByID(id);
      if (!mounted) return;
      if (item != null) {
        context.pushNamed('/info/', arguments: item);
      } else {
        setState(() => message = '资料暂时不可用，请重试');
      }
    } finally {
      if (mounted) setState(() => _metadataLoading = false);
    }
  }

  @override
  void dispose() {
    _closed = true;
    _play?.cancel();
    widget.session.removeListener(_sync);
    sources.dispose();
    matchingSearch.dispose();
    unawaited(media.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(
            widget.work.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  sources,
                  widget.session,
                  matchingSearch,
                ]),
                builder: (context, _) => ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: media.controller == null
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Center(child: Text('选择来源、线路和剧集后播放')),
                            )
                          : WebPlayerSurface(controller: media.controller!),
                    ),
                    const SizedBox(height: 12),
                    if (busy) const LinearProgressIndicator(),
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(message!),
                      ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '播放源',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.session.searching ||
                            matchingSearch.searching)
                          const Text('仍在检索…', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: matchingSearch.searching
                          ? null
                          : () => matchingSearch.submit(
                              ContentQuery(
                                widget.work.title,
                                group: widget.work.primary.group,
                              ),
                            ),
                      icon: const Icon(LucideIcons.search, size: 16),
                      label: const Text('用完整片名继续找源'),
                    ),
                    const Text(
                      '同名候选保留匹配证据；目录有效不代表已经试播。',
                      style: TextStyle(fontSize: 12),
                    ),
                    for (final binding in sources.bindings)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sources.provider(binding.hit).name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '${matchContent(widget.work.primary, binding.hit) == ContentMatch.possible ? '同名候选 · 手动选择' : '作品匹配'} · ${_status(binding)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              if (binding.status ==
                                  ContentDirectoryStatus.ready)
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    for (final line in binding.lines)
                                      ChoiceChip(
                                        label: Text(line.name),
                                        selected:
                                            identical(
                                              sources.selected,
                                              binding,
                                            ) &&
                                            sources.selectedLine?.id == line.id,
                                        onSelected: (_) =>
                                            _select(binding, line),
                                      ),
                                  ],
                                ),
                              if (binding.status ==
                                      ContentDirectoryStatus.failed ||
                                  binding.status ==
                                      ContentDirectoryStatus
                                          .verificationRequired)
                                TextButton(
                                  onPressed: () => sources.retry(binding),
                                  child: const Text('重试目录'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (sources.bindings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('暂未找到来源，可以返回修改名称或等待其他检索结果'),
                      ),
                    if (sources.loadingEpisodes)
                      const LinearProgressIndicator(),
                    if (sources.episodeError != null)
                      Text('剧集加载失败（${sources.episodeError}），请重新选择线路'),
                    if (sources.selected != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '选集',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final episode in sources.episodes)
                            ShadButton.outline(
                              onPressed: () => _playEpisode(episode),
                              child: Text(episode.title),
                            ),
                        ],
                      ),
                      if (!sources.loadingEpisodes && sources.episodes.isEmpty)
                        const Text('该线路暂未提供剧集'),
                    ],
                    for (final hit in widget.work.hits)
                      if (hit.metadataId?.startsWith('bangumi:') == true)
                        TextButton(
                          onPressed: _metadataLoading
                              ? null
                              : () => _metadata(hit),
                          child: const Text('查看 Bangumi 资料与原播放入口'),
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

  String _status(ContentSourceBinding binding) => switch (binding.status) {
    ContentDirectoryStatus.pending => '目录验证中',
    ContentDirectoryStatus.ready => '线路可选 · 未试播',
    ContentDirectoryStatus.empty => '未取得有效目录',
    ContentDirectoryStatus.failed => '目录失败（${binding.errorCode}）',
    ContentDirectoryStatus.verificationRequired => '需要来源验证，可使用原作品找源入口完成验证',
  };
}
