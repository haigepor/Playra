import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_card.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/services/source/content_providers.dart';
import 'package:kazumi/services/source/content_search.dart';
import '../secondary/secondary_theme.dart';
import '../settings/modern_back_button.dart';
import '../widgets/modern_page_art.dart';
import 'package:kazumi/services/source/sdk_playback_entry.dart';
import 'package:kazumi/services/plugin/rule_engine_models.dart'
    show RuleCancelToken;

class ContentSearchScreen extends StatefulWidget {
  const ContentSearchScreen({
    super.key,
    this.providers,
    this.initialGroup,
    this.initialKeyword = '',
  });
  final List<ContentSearchProvider>? providers;
  final ContentGroup? initialGroup;
  final String initialKeyword;
  @override
  State<ContentSearchScreen> createState() => _ContentSearchScreenState();
}

class _ContentSearchScreenState extends State<ContentSearchScreen> {
  late ContentSearchSession session;
  late final Future<void> ready;
  late final TextEditingController input;
  final inputFocus = FocusNode();
  String? openingWork;
  int navigationGeneration = 0;
  RuleCancelToken? openingCancel;
  ContentGroup? group;
  String region = '';
  bool submitted = false;
  @override
  void initState() {
    super.initState();
    session = ContentSearchSession(widget.providers ?? contentProviders());
    ready = Future.value();
    input = TextEditingController(text: widget.initialKeyword);
    group = widget.initialGroup;
    if (group != null &&
        !session.providers.any((p) => p.groups.contains(group))) {
      group = null;
    }
    if (widget.initialKeyword.isNotEmpty) unawaited(_search());
  }

  Future<void> _search() async {
    await ready;
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (input.text.trim().isEmpty) return;
    setState(() {
      submitted = true;
      openingWork = null;
      navigationGeneration++;
      openingCancel?.cancel('query changed');
    });
    await session.submit(
      ContentQuery(input.text, group: group, region: region),
    );
  }

  @override
  void dispose() {
    session.dispose();
    input.dispose();
    inputFocus.dispose();
    openingCancel?.cancel('disposed');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernSecondaryScope(
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
          toolbarHeight: 56,
          leading: const ModernBackButton(),
          title: const Text('搜索作品'),
          titleTextStyle: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontSize: PlayraType.title,
            fontWeight: FontWeight.w700,
          ),
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ModernPageArt(
                kind: ModernPageArtKind.discover,
                child: AnimatedBuilder(
                  animation: session,
                  builder: (context, _) {
                    // 一次重建只排序一次，滚动创建卡片时复用同一结果快照。
                    final works = session.works;
                    return Column(
                      children: [
                        _searchHeader(context),
                        Expanded(
                          child: !submitted
                              ? const Center(
                                  child: SingleChildScrollView(
                                    child: SecondaryEmptyState(
                                      title: '找到下一部想看的作品',
                                      description: '选择频道，输入名称开始搜索',
                                    ),
                                  ),
                                )
                              : CustomScrollView(
                                  key: const ValueKey('content-search-results'),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  slivers: [
                                    SliverToBoxAdapter(
                                      child: _progress(context),
                                    ),
                                    if (works.isEmpty)
                                      SliverFillRemaining(
                                        hasScrollBody: false,
                                        child: _empty(),
                                      )
                                    else ...[
                                      SliverPadding(
                                        padding: const EdgeInsets.fromLTRB(
                                          PlayraSpace.lg,
                                          PlayraSpace.xs,
                                          PlayraSpace.lg,
                                          PlayraSpace.md,
                                        ),
                                        sliver: SliverList.builder(
                                          itemCount: works.length,
                                          itemBuilder: (context, index) =>
                                              _resultTile(
                                                context,
                                                works[index],
                                              ),
                                        ),
                                      ),
                                      if (session.hasMore)
                                        SliverToBoxAdapter(
                                          child: Padding(
                                            padding: const EdgeInsets.all(
                                              PlayraSpace.lg,
                                            ),
                                            child: PlayraButton.outline(
                                              onPressed: session.searching
                                                  ? null
                                                  : session.loadMore,
                                              child: const Text('加载更多'),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _searchHeader(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PlayraSpace.lg,
      PlayraSpace.sm,
      PlayraSpace.lg,
      PlayraSpace.md,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField(context),
        const SizedBox(height: 10),
        _groupFilters(context),
        if (group == ContentGroup.series) ...[
          const SizedBox(height: PlayraSpace.sm),
          Align(alignment: Alignment.centerLeft, child: _regionFilter(context)),
        ],
      ],
    ),
  );

  Widget _groupFilters(BuildContext context) {
    final available = session.providers.expand((p) => p.groups).toSet();
    final groups = <ContentGroup?>[
      null,
      ...ContentGroup.values.where(available.contains),
    ];
    // 只呈现已登记来源覆盖的分类；退役 SDK 不留下空入口。
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < groups.length; index++) ...[
            if (index > 0) const SizedBox(width: PlayraSpace.compact),
            Semantics(
              selected: group == groups[index],
              inMutuallyExclusiveGroup: true,
              child: PlayraButton.ghost(
                onPressed: () {
                  setState(() {
                    group = groups[index];
                    region = '';
                  });
                  if (submitted) unawaited(_search());
                },

                child: Text(groups[index]?.label ?? '全部'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _searchField(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    // 编辑器与焦点不随每个按键重建；仅清空按钮监听输入，保留 IME composing/selection。
    return Row(
      children: [
        Expanded(
          child: PlayraTextField(
            key: const ValueKey('content-search-input'),
            controller: input,
            focusNode: inputFocus,

            autocorrect: false,
            keyboardType: TextInputType.text,
            // Android 的禁用建议会附带 visible-password 标记，触发部分手机的安全键盘。
            enableSuggestions: true,
            smartDashesType: SmartDashesType.disabled,
            smartQuotesType: SmartQuotesType.disabled,
            textInputAction: TextInputAction.search,

            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: '搜索作品名称',
              fillColor: c.surfaceContainerLow,
              filled: true,
              prefixIconConstraints: const BoxConstraints(
                minWidth: 44,
                minHeight: 48,
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 48,
                minHeight: 48,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: PlayraSpace.md,
                vertical: 13,
              ),
              prefixIcon: Icon(
                LucideIcons.search,
                size: 20,
                color: c.onSurfaceVariant,
              ),
              suffixIcon: ValueListenableBuilder<TextEditingValue>(
                valueListenable: input,
                builder: (_, value, _) => Visibility(
                  visible: value.text.isNotEmpty,
                  maintainSize: true,
                  maintainState: true,
                  maintainAnimation: true,
                  child: PlayraIconButton(
                    tooltip: '清空输入',
                    onPressed: () {
                      input.clear();
                      inputFocus.requestFocus();
                    },
                    icon: const Icon(LucideIcons.x, size: 16),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: PlayraSpace.sm),
        PlayraButton(onPressed: _search, child: const Text('搜索')),
      ],
    );
  }

  Widget _resultTile(BuildContext context, ContentWork work) {
    final c = Theme.of(context).colorScheme;
    final sources = work.hits
        .where((h) => session.provider(h.providerId).canPlay)
        .map((h) => h.providerId)
        .toSet()
        .length;
    return Padding(
      key: ValueKey(work.id),
      padding: const EdgeInsets.only(bottom: 10),
      child: PlayraCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          onTap: openingWork == null ? () => _openWork(work) : null,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
              final coverWidth = constraints.maxWidth < 340 || largeText
                  ? 64.0
                  : 72.0;
              final coverHeight = coverWidth * 1.5;
              return Padding(
                padding: const EdgeInsets.all(PlayraSpace.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (work.cover.isEmpty)
                      Container(
                        width: coverWidth,
                        height: coverHeight,
                        decoration: BoxDecoration(
                          color: c.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          LucideIcons.film,
                          size: 24,
                          color: c.onSurfaceVariant,
                        ),
                      )
                    else
                      NetworkImgLayer(
                        src: work.cover,
                        width: coverWidth,
                        height: coverHeight,
                        borderRadius: BorderRadius.circular(9),
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: coverHeight),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              work.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    fontSize: 15,
                                    height: 1.4,
                                    fontWeight: FontWeight.w600,
                                    color: c.onSurface,
                                  ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              [
                                if (work.primary.year != null)
                                  '${work.primary.year}',
                                work.primary.group?.label ?? '待分类',
                              ].join(' · '),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: c.onSurfaceVariant),
                            ),
                            const SizedBox(height: PlayraSpace.md),
                            Row(
                              children: [
                                SvgPicture.asset(
                                  sources == 0
                                      ? 'assets/images/modern-work-info.svg'
                                      : 'assets/images/modern-source-candidates.svg',
                                  width: 18,
                                  height: 18,
                                  excludeFromSemantics: true,
                                ),
                                const SizedBox(width: PlayraSpace.compact),
                                Expanded(
                                  child: Text(
                                    sources == 0 ? '作品资料' : '$sources 个候选来源',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: sources == 0
                                              ? c.onSurfaceVariant
                                              : c.primary,
                                          fontSize: PlayraType.small,
                                        ),
                                  ),
                                ),
                                const SizedBox(width: PlayraSpace.sm),
                                if (openingWork == work.id)
                                  SizedBox.square(
                                    dimension: 18,
                                    child: PlayraSpinner(),
                                  )
                                else
                                  Icon(
                                    LucideIcons.chevronRight,
                                    size: 17,
                                    color: c.onSurfaceVariant,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _openWork(ContentWork work) async {
    final generation = ++navigationGeneration;
    openingCancel?.cancel('replaced');
    final cancel = openingCancel = RuleCancelToken();
    bool current() =>
        mounted &&
        generation == navigationGeneration &&
        session.works.any((item) => identical(item, work));
    inputFocus.unfocus();
    setState(() => openingWork = work.id);
    try {
      // SDK 原生动漫直接使用自身作品身份，不强制匹配 Bangumi 才允许进入。
      final sdkEntry = SdkPlaybackEntry.fromWork(work, [
        for (final hit in work.hits) session.provider(hit.providerId),
      ]);
      if (sdkEntry != null) {
        if (!current()) return;
        await context.pushNamed('/info/', arguments: sdkEntry);
        return;
      }
      if (current()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('当前作品没有可用的 Lumina 入口')));
      }
    } catch (_) {
      if (mounted && current()) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('作品入口加载失败，请重试')));
      }
    } finally {
      cancel.cancel('navigation completed');
      if (mounted && generation == navigationGeneration) {
        setState(() => openingWork = null);
      }
    }
  }

  static const _regions = {
    '': '全部地区',
    'CN': '国产',
    'HK': '港剧',
    'TW': '台剧',
    'JP': '日剧',
    'KR': '韩剧',
    'US': '美剧',
    'GB': '英剧',
    'TH': '泰剧',
  };

  Widget _regionFilter(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return PlayraPopupMenu<String>(
      tooltip: '选择剧集地区',
      initialValue: region,

      itemBuilder: (_) => [
        for (final entry in _regions.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onSelected: (value) {
        setState(() => region = value);
        if (submitted) unawaited(_search());
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(horizontal: PlayraSpace.md),
        decoration: BoxDecoration(
          color: c.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _regions[region]!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
            ),
            const SizedBox(width: PlayraSpace.sm),
            Icon(LucideIcons.chevronDown, size: 14, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _empty() => Center(
    child: SingleChildScrollView(
      child: SecondaryEmptyState(
        title: session.searching
            ? '正在查找作品'
            : !session.hasProviders
            ? '${group?.label ?? '该频道'}来源尚未接入'
            : '暂未找到作品',
        description: session.searching
            ? '正在检索，结果返回后立即展示'
            : !session.hasProviders
            ? '已预留接入位置，后续来源接入后会在这里展示。'
            : session.failures > 0
            ? '暂未取得结果，部分来源失败；可以展开进度重试'
            : '没有匹配的作品，试试其他名称',
        action: session.hasMore
            ? PlayraButton.outline(
                onPressed: session.searching ? null : session.loadMore,
                child: const Text('继续检索下一页'),
              )
            : null,
      ),
    ),
  );

  Widget _progress(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      PlayraSpace.lg,
      0,
      PlayraSpace.lg,
      PlayraSpace.sm,
    ),
    child: PlayraExpansionTile(
      key: const ValueKey('content-search-progress'),

      title: Text(
        session.searching
            ? '已完成 ${session.completed}/${session.statuses.length} · 继续检索…'
            : '检索完成 · ${session.works.length} 个作品${session.failures > 0 ? ' · ${session.failures} 个来源需重试' : ''}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      leading: session.searching
          ? const SizedBox(width: 16, height: 16, child: PlayraSpinner())
          : const Icon(LucideIcons.listFilter, size: 16),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                ((MediaQuery.sizeOf(context).height -
                            MediaQuery.viewInsetsOf(context).bottom) *
                        .25)
                    .clamp(48, 180),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in session.statuses.entries)
                PlayraListTile(
                  title: Text(session.provider(entry.key).name),
                  subtitle: Text(switch (entry.value) {
                    ContentProviderStatus.queued => '排队中',
                    ContentProviderStatus.searching => '检索中',
                    ContentProviderStatus.success => '已返回',
                    ContentProviderStatus.empty => '无命中',
                    ContentProviderStatus.failed =>
                      '请求失败（${session.errors[entry.key]}）',
                    ContentProviderStatus.verificationRequired => '需要来源验证',
                  }),
                  trailing:
                      entry.value == ContentProviderStatus.failed ||
                          entry.value ==
                              ContentProviderStatus.verificationRequired
                      ? PlayraButton.ghost(
                          onPressed: session.searching
                              ? null
                              : () => session.retry(entry.key),
                          child: const Text('重试'),
                        )
                      : null,
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
