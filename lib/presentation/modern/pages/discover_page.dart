import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/presentation/shared/tab_shell.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/theme_provider.dart';
import 'package:kazumi/modules/history/history_module.dart';
import 'package:kazumi/navigation.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/repositories/history_repository.dart';
import 'package:kazumi/services/player/history_playback_service.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;
import 'package:kazumi/services/storage/storage.dart';
import '../home/modern_home_controller.dart';
import '../home/home_catalog.dart';
import '../home/modern_home_view.dart';
import '../home/home_theme.dart';
import '../miomedia/miomedia_home_controller.dart';
import '../miomedia/miomedia_rank_view.dart' show mioRankCategory;
import 'package:kazumi/services/source/content_search.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/platform/lumina_support.dart';
import 'package:kazumi/services/source/lumina/lumina_service.dart';
import 'package:kazumi/services/source/lumina/lumina_home_controller.dart';
import 'package:kazumi/services/source/lumina/lumina_playback_provider.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/source/sdk_rank_controller.dart';

/// 路由适配层：新版视图不直接读取全局容器或启动独立业务仓库。
class ModernDiscoverPage extends StatefulWidget {
  const ModernDiscoverPage({super.key});
  @override
  State<ModernDiscoverPage> createState() => _ModernDiscoverPageState();
}

class _ModernDiscoverPageState extends State<ModernDiscoverPage>
    with KazumiDialogOwner {
  late final ModernHomeController controller;
  late final MioMediaService mediaService;
  late final MioHomeController media;
  LuminaService? animeService;
  LuminaHomeController? anime;
  late final SdkRankController ranking;
  String? _rankingKey;
  bool _changingTheme = false;
  Timer? _backgroundDeadline;
  bool _backgroundStarted = false, _channelsWarmed = false;

  @override
  void initState() {
    super.initState();
    final repository = inject<IHistoryRepository>();
    controller = ModernHomeController(
      loadProgressiveCatalog: (onUpdate) => HomeCatalog.load(
        rules: inject<PluginsController>().pluginList,
        force: false,
        onUpdate: onUpdate,
      ),
      loadDetail: HomeCatalog.loadDetail,
      readHistory: repository.getAllHistories,
      historyChanges: repository.changes,
    );
    unawaited(controller.refresh(includeCatalog: false));
    mediaService = MioMediaService();
    media = MioHomeController(mediaService);
    unawaited(media.bootstrap());
    if (luminaSupported) {
      animeService = LuminaService();
      anime = LuminaHomeController(animeService!);
    }
    ranking = SdkRankController(lumina: animeService, mio: mediaService);
    controller.addListener(_syncRanking);
    anime?.addListener(_syncRanking);
    media.addListener(_syncRanking);
    _syncRanking();
    final primary =
        anime?.bootstrap(warmOtherChannels: false) ?? Future<void>.value();
    unawaited(
      Future.wait([
        primary,
        media.firstCatalogReady,
      ]).then((_) => _startBackground()),
    );
    unawaited(
      primary.then((_) {
        if (_backgroundStarted) _startBackground();
      }),
    );
    // 先让主频道与影视首屏使用运行名额，资料补全最多延后四秒。
    _backgroundDeadline = Timer(const Duration(seconds: 4), _startBackground);
  }

  void _startBackground() {
    if (!mounted) return;
    if (!_backgroundStarted) {
      _backgroundStarted = true;
      unawaited(controller.refreshCatalog());
    }
    if (!_channelsWarmed && anime?.items.isNotEmpty == true) {
      _channelsWarmed = true;
      // 先提交主频道的真实首屏，再启动串行的小页预热。
      unawaited(
        WidgetsBinding.instance.endOfFrame.then((_) async {
          if (mounted) await anime!.warmChannels();
        }),
      );
    }
  }

  void _syncRanking({bool refresh = false}) {
    final feed = controller.feed;
    final bucket = switch (feed) {
      HomeFeed.japanese => 'japanese',
      HomeFeed.chinese => 'chinese',
      HomeFeed.animeMovies => 'movies',
      HomeFeed.season => 'season',
      _ => 'all',
    };
    final channel = feed.isGeneralCategory || feed.isAnimeCategory
        ? anime?.browseChannels(bucket).firstOrNull?.id
        : null;
    final readyChannel =
        channel != null && anime!.channelItems.containsKey(channel)
        ? channel
        : null;
    final mixed = feed.isGeneralCategory || feed == HomeFeed.screen;
    final mioCategories = {
      for (final kind in const [MioKind.movie, MioKind.series])
        if (media.categoryIds[kind] != null && media.categoryIds[kind] != '0')
          media.categoryIds[kind]!,
    }.toList()..sort();
    final mioCategory = mixed ? null : mioRankCategory(media, feed);
    final discovering = media.discovering || anime?.loading == true;
    final key =
        '$readyChannel|${mixed ? mioCategories.join(',') : mioCategory}|$discovering';
    if (!refresh && key == _rankingKey) return;
    _rankingKey = key;
    unawaited(
      ranking.load(
        luminaChannelId: readyChannel,
        mioCategoryId: mioCategory,
        mioCategoryIds: mixed ? mioCategories : null,
        refresh: refresh,
        discovering: discovering,
      ),
    );
  }

  void _search(BuildContext pageContext) {
    context.pushNamed(
      '/search/',
      arguments: switch (controller.feed) {
        HomeFeed.screen ||
        HomeFeed.movies ||
        HomeFeed.variety => ContentGroup.screen,
        HomeFeed.television => ContentGroup.series,
        HomeFeed.comicDrama => ContentGroup.comicDrama,
        _ => controller.feed.isAnimeCategory ? ContentGroup.anime : null,
      },
    );
  }

  Future<void> _resume(History history) async {
    if (dialogs.isRunning) return;
    await dialogs.run((task) async {
      final cancelToken = RuleCancelToken();
      final result = await task.loading(
        message: '获取中',
        barrierDismissible: false,
        onCancel: cancelToken.cancel,
        action: () => inject<HistoryPlaybackService>().open(
          history,
          cancelToken: cancelToken,
        ),
      );
      switch (result) {
        case HistoryPlaybackReady(:final args):
          task.withContext(
            (context) => context.pushNamed('/video/', arguments: args),
          );
        case HistoryPlaybackUnavailable(:final reason):
          KazumiDialog.showToast(message: reason);
      }
    }, errorMessage: '暂时无法继续播放，请稍后重试');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller.setVisible(!RouteVisibility.isCoveredOf(context));
  }

  Future<void> _toggleTheme() async {
    if (_changingTheme) return;
    _changingTheme = true;
    final theme = context.read<ThemeProvider>();
    final mode = theme.isEffectiveDark() ? ThemeMode.light : ThemeMode.dark;
    try {
      // 先持久化，再通知全局主题，写入失败时不制造界面与设置不一致。
      await GStorage.putSetting(SettingsKeys.themeMode, mode.name);
      if (mounted) theme.setThemeMode(mode);
    } catch (_) {
      KazumiDialog.showToast(message: '保存主题失败，请稍后重试');
    } finally {
      _changingTheme = false;
    }
  }

  @override
  void dispose() {
    _backgroundDeadline?.cancel();
    controller.removeListener(_syncRanking);
    anime?.removeListener(_syncRanking);
    media.removeListener(_syncRanking);
    ranking.dispose();
    anime?.dispose();
    animeService?.dispose();
    media.dispose();
    mediaService.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) => ModernHomeView(
        controller: controller,
        media: media,
        onMediaDetails: (item) => context.pushNamed('/info/', arguments: item),
        anime: anime,
        ranking: ranking,
        onRankDetails: (entry) => context.pushNamed('/info/', arguments: entry),
        refreshRanking: () => _syncRanking(refresh: true),
        onAnimeDetails: anime == null
            ? null
            : (item) => context.pushNamed(
                '/info/',
                arguments: SdkPlaybackEntry(
                  title: item.title,
                  cover: item.cover,
                  autoPlay: false,
                  sources: [
                    SdkSourceBinding(
                      provider: LuminaPlaybackProvider(animeService!),
                      contentId: item.id,
                      seed: item,
                    ),
                  ],
                ),
              ),
        onAnimeBanner: anime == null
            ? null
            : (item) => context.pushNamed(
                '/info/',
                arguments: SdkPlaybackEntry(
                  title: item.title,
                  cover: item.cover,
                  autoPlay: false,
                  sources: [
                    SdkSourceBinding(
                      provider: LuminaPlaybackProvider(animeService!),
                      contentId: item.videoId,
                    ),
                  ],
                ),
              ),
        refreshAnime: anime == null
            ? null
            : () => anime!.bootstrap(force: true),
        onSearch: () => _search(context),
        // 交给主壳层切换，移动端不会重建整个分页缓存。
        onCalendar: () {
          final select = TabDestinationScope.maybeOf(context);
          if (select != null) {
            select(1);
          } else {
            (rootNavigatorKey.currentContext ?? context).navigate(
              '/tab/timeline/',
            );
          }
        },
        onBrowse: (tag) => context.pushNamed(
          tag.isEmpty ? '/search/' : '/search/${Uri.encodeComponent(tag)}',
        ),
        onHistory: () => context.pushNamed('/settings/history/'),
        onToggleTheme: _toggleTheme,
        onDetails: (item) => context.pushNamed('/info/', arguments: item),
        onResume: _resume,
      ),
    ),
  );
}
