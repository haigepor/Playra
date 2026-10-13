import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/source/content_providers.dart';
import 'package:kazumi/services/source/content_search.dart';
import '../secondary/secondary_theme.dart';
import '../settings/modern_back_button.dart';
import 'package:kazumi/request/apis/bangumi_api.dart';
import 'package:kazumi/modules/bangumi/bangumi_item.dart';
import 'package:kazumi/pages/info/source_search_entry.dart';
import 'package:kazumi/services/source/content_search_playback.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
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
    session = ContentSearchSession(
      widget.providers ??
          contentProviders(inject<PluginsController>().pluginList),
    );
    ready =
        widget.providers == null &&
            inject<PluginsController>().pluginList.isEmpty
        ? _loadBundledRules()
        : Future.value();
    input = TextEditingController(text: widget.initialKeyword);
    group = widget.initialGroup;
    if (widget.initialKeyword.isNotEmpty) unawaited(_search());
  }

  Future<void> _loadBundledRules() async {
    final providers = await loadContentProviders(const []);
    if (!mounted) {
      for (final provider in providers) {
        provider.dispose();
      }
      return;
    }
    session.dispose();
    setState(() => session = ContentSearchSession(providers));
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
          leading: const ModernBackButton(),
          title: const Text('搜索作品'),
          actions: [
            IconButton(
              tooltip: '番组资料高级搜索',
              icon: const Icon(LucideIcons.slidersHorizontal),
              onPressed: () => context.pushNamed('/search/metadata'),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: AnimatedBuilder(
                animation: session,
                builder: (context, _) => Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: _searchField(context),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      // 五个频道在 320px 也保留完整标签；缩小内边距，保留 48dp 触摸高度。
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          tabBarTheme: Theme.of(context).tabBarTheme.copyWith(
                            labelPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                            ),
                          ),
                        ),
                        child: SecondaryTabs(
                          labels: [
                            '全部',
                            ...ContentGroup.values.map((g) => g.label),
                          ],
                          selected: group == null ? 0 : group!.index + 1,
                          onChanged: (index) {
                            setState(() {
                              group = index == 0
                                  ? null
                                  : ContentGroup.values[index - 1];
                              region = '';
                            });
                            if (submitted) unawaited(_search());
                          },
                        ),
                      ),
                    ),
                    if (group == ContentGroup.series)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _regionFilter(context),
                        ),
                      ),
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
                                SliverToBoxAdapter(child: _progress(context)),
                                if (session.works.isEmpty)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _empty(),
                                  )
                                else ...[
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                      16,
                                      4,
                                      16,
                                      12,
                                    ),
                                    sliver: SliverList.builder(
                                      itemCount: session.works.length,
                                      itemBuilder: (context, index) =>
                                          _resultTile(
                                            context,
                                            session.works[index],
                                          ),
                                    ),
                                  ),
                                  if (session.hasMore)
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.all(16),
                                        child: ShadButton.outline(
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
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Widget _searchField(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    // 编辑器与焦点不随每个按键重建；仅清空按钮监听输入，保留 IME composing/selection。
    return TextField(
      key: const ValueKey('content-search-input'),
      controller: input,
      focusNode: inputFocus,
      cursorColor: c.primary,
      autocorrect: false,
      enableSuggestions: false,
      smartDashesType: SmartDashesType.disabled,
      smartQuotesType: SmartQuotesType.disabled,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium,
      onSubmitted: (_) => _search(),
      decoration: InputDecoration(
        hintText: '搜索作品名称',
        fillColor: c.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        prefixIcon: Icon(
          LucideIcons.search,
          size: 20,
          color: c.onSurfaceVariant,
        ),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: input,
              builder: (_, value, _) => Visibility(
                visible: value.text.isNotEmpty,
                maintainSize: true,
                maintainState: true,
                maintainAnimation: true,
                child: IconButton(
                  tooltip: '清空输入',
                  onPressed: () {
                    input.clear();
                    inputFocus.requestFocus();
                  },
                  icon: const Icon(LucideIcons.x, size: 16),
                ),
              ),
            ),
            TextButton(onPressed: _search, child: const Text('搜索')),
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _resultTile(BuildContext context, ContentWork work) {
    final c = Theme.of(context).colorScheme;
    final sources = work.hits
        .where((h) => session.provider(h.providerId).canPlay)
        .map((h) => h.providerId)
        .toSet()
        .length;
    return Card(
      key: ValueKey(work.id),
      margin: const EdgeInsets.only(bottom: 10),
      color: c.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: work.cover.isEmpty
            ? const SizedBox(
                width: 48,
                height: 64,
                child: Icon(LucideIcons.film),
              )
            : NetworkImgLayer(
                src: work.cover,
                width: 48,
                height: 64,
                borderRadius: BorderRadius.circular(6),
              ),
        title: Text(
          work.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          [
            work.primary.group?.label ?? '待分类',
            if (work.primary.year != null) '${work.primary.year}',
            sources == 0 ? '作品资料' : '$sources 个候选来源',
          ].join(' · '),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
        trailing: openingWork == work.id
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(LucideIcons.chevronRight, size: 18),
        onTap: openingWork == null ? () => _openWork(work) : null,
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
      Object? entry;
      for (final hit in work.hits) {
        final provider = session.provider(hit.providerId);
        if (provider is BangumiContentProvider) entry = provider.entry(hit);
        if (provider is MioContentProvider) entry = provider.entry(hit);
        if (entry != null) break;
      }
      if (entry == null && work.primary.group == ContentGroup.anime) {
        // 规则只有标题/链接时自动匹配唯一真实身份，不创建假 ID 或确认弹窗。
        final result = await BangumiApi.bangumiSearch(
          work.title,
          limit: 20,
        ).timeout(const Duration(seconds: 20));
        if (!mounted || !current()) return;
        entry = uniqueAnimeMetadata(work.primary, result?.items ?? []);
      }
      if (!mounted || !current()) return;
      if (entry == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('未找到对应作品资料，请尝试更完整的名称')));
        return;
      }
      Object destination = entry;
      if (entry is BangumiItem) {
        final candidate = await prepareSearchPlayback(
          entry,
          work,
          session,
          cancel,
        );
        if (!mounted || !current()) return;
        if (candidate == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('来源目录预加载失败，请重试'),
              action: SnackBarAction(
                label: '重试',
                onPressed: () => _openWork(work),
              ),
            ),
          );
          return;
        }
        cancel.cancel('ready');
        destination = SourceSearchEntry(
          item: entry,
          playbackArgs: candidate.args(entry),
          rules: session.providers.whereType<RuleContentProvider>().map(
            (p) => p.plugin,
          ),
        );
      } else if (entry is MioVideo) {
        destination = MioSearchEntry(entry);
      }
      if (!mounted || !current()) return;
      await context.pushNamed('/info/', arguments: destination);
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
    return PopupMenuButton<String>(
      tooltip: '选择剧集地区',
      initialValue: region,
      color: c.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.outline),
      ),
      itemBuilder: (_) => [
        for (final entry in _regions.entries)
          PopupMenuItem(value: entry.key, child: Text(entry.value)),
      ],
      onSelected: (value) {
        setState(() => region = value);
        if (submitted) unawaited(_search());
      },
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
            const SizedBox(width: 8),
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
            ? ShadButton.outline(
                onPressed: session.searching ? null : session.loadMore,
                child: const Text('继续检索下一页'),
              )
            : null,
      ),
    ),
  );

  Widget _progress(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      key: const ValueKey('content-search-progress'),
      dense: true,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      textColor: Theme.of(context).colorScheme.onSurfaceVariant,
      collapsedTextColor: Theme.of(context).colorScheme.onSurfaceVariant,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      collapsedIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      title: Text(
        session.searching
            ? '已完成 ${session.completed}/${session.statuses.length} · 继续检索…'
            : '检索完成 · ${session.works.length} 个作品${session.failures > 0 ? ' · ${session.failures} 个来源需重试' : ''}',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      leading: session.searching
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(LucideIcons.listFilter, size: 18),
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
                ListTile(
                  dense: true,
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
                      ? TextButton(
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
