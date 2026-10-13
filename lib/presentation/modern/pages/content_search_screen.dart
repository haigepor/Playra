import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:kazumi/bean/card/network_img_layer.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/source/content_providers.dart';
import 'package:kazumi/services/source/content_search.dart';
import '../home/home_theme.dart';
import 'content_work_page.dart';

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
  late final ContentSearchSession session;
  late final TextEditingController input;
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
    input = TextEditingController(text: widget.initialKeyword);
    group = widget.initialGroup;
    if (widget.initialKeyword.isNotEmpty) unawaited(_search());
  }

  Future<void> _search() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (input.text.trim().isEmpty) return;
    setState(() => submitted = true);
    await session.submit(
      ContentQuery(input.text, group: group, region: region),
    );
  }

  @override
  void dispose() {
    session.dispose();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(
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
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const ValueKey('content-search-input'),
                              controller: input,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _search(),
                              decoration: const InputDecoration(
                                hintText: '搜索作品名称',
                                prefixIcon: Icon(LucideIcons.search),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ShadButton(
                            onPressed: _search,
                            child: const Text('搜索'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final choice in <ContentGroup?>[
                            null,
                            ...ContentGroup.values,
                          ])
                            ChoiceChip(
                              label: Text(choice?.label ?? '全部'),
                              selected: group == choice,
                              onSelected: (_) {
                                setState(() {
                                  group = choice;
                                  region = '';
                                });
                                if (submitted) unawaited(_search());
                              },
                            ),
                        ],
                      ),
                    ),
                    if (group == ContentGroup.series)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: DropdownButton<String>(
                          value: region,
                          isExpanded: true,
                          hint: const Text('地区'),
                          items: [
                            for (final entry in const {
                              '': '全部地区',
                              'CN': '国产',
                              'HK': '港剧',
                              'TW': '台剧',
                              'JP': '日剧',
                              'KR': '韩剧',
                              'US': '美剧',
                              'GB': '英剧',
                              'TH': '泰剧',
                            }.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                          onChanged: (value) {
                            setState(() => region = value ?? '');
                            if (submitted) unawaited(_search());
                          },
                        ),
                      ),
                    if (submitted) _progress(context),
                    Expanded(
                      child: !submitted
                          ? const Center(child: Text('选择频道，输入名称开始搜索'))
                          : session.works.isEmpty
                          ? _empty()
                          : ListView.builder(
                              key: const ValueKey('content-search-results'),
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                              itemCount: session.works.length + 1,
                              itemBuilder: (context, index) {
                                if (index == session.works.length) {
                                  return session.hasMore
                                      ? Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: ShadButton.outline(
                                            onPressed: session.searching
                                                ? null
                                                : session.loadMore,
                                            child: const Text('加载更多'),
                                          ),
                                        )
                                      : const SizedBox.shrink();
                                }
                                final work = session.works[index];
                                final sources = work.hits
                                    .where(
                                      (h) => session
                                          .provider(h.providerId)
                                          .canPlay,
                                    )
                                    .map((h) => h.providerId)
                                    .toSet()
                                    .length;
                                return Card(
                                  key: ValueKey(work.id),
                                  margin: const EdgeInsets.only(bottom: 10),
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
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                    title: Text(
                                      work.title,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        work.primary.group?.label ?? '待分类',
                                        if (work.primary.year != null)
                                          '${work.primary.year}',
                                        sources == 0
                                            ? '资料条目 · 继续查找来源'
                                            : '$sources 个候选来源',
                                      ].join(' · '),
                                    ),
                                    trailing: const Icon(
                                      LucideIcons.chevronRight,
                                      size: 18,
                                    ),
                                    onTap: () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => ContentWorkPage(
                                          work: work,
                                          session: session,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
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

  Widget _empty() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            session.searching
                ? '正在检索，结果返回后立即展示'
                : !session.hasProviders
                ? '${group?.label ?? '该频道'}来源尚未接入'
                : session.failures > 0
                ? '暂未取得结果，部分来源失败；可以展开进度重试'
                : '没有匹配的作品，试试其他名称',
            textAlign: TextAlign.center,
          ),
          if (session.hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: ShadButton.outline(
                onPressed: session.searching ? null : session.loadMore,
                child: const Text('继续检索下一页'),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _progress(BuildContext context) => ExpansionTile(
    key: const ValueKey('content-search-progress'),
    dense: true,
    title: Text(
      session.searching
          ? '已完成 ${session.completed}/${session.statuses.length} · 继续检索…'
          : '检索完成 · ${session.works.length} 个作品 · ${session.failures} 个来源需重试',
      style: const TextStyle(fontSize: 12),
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
        constraints: const BoxConstraints(maxHeight: 180),
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
  );
}
