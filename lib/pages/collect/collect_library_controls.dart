part of 'collect_library_view.dart';

class _CollectCategories extends StatelessWidget {
  const _CollectCategories({
    super.key,
    required this.controller,
    required this.selected,
    required this.count,
  });

  final TabController controller;
  final ValueListenable<CollectType?> selected;
  final int Function(CollectType?) count;

  @override
  Widget build(BuildContext context) {
    return PlayraTabBar(
      key: const PageStorageKey('collect-filter-strip'),
      controller: controller,
      isScrollable: true,

      tabs: [
        for (final type in _collectCategories)
          Tab(
            height: 48,
            child: Semantics(
              label: '${type?.label ?? '全部'}，${count(type)} 部',
              excludeSemantics: true,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ValueListenableBuilder(
                    valueListenable: selected,
                    builder: (context, value, _) => Text(
                      type?.label ?? '全部',
                      textAlign: TextAlign.center,
                      style: value == type
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CollectLayoutSwitch extends StatelessWidget {
  const _CollectLayoutSwitch({required this.value, required this.onChanged});

  final CollectLayout value;
  final ValueChanged<CollectLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (final layout in [CollectLayout.cards, CollectLayout.list])
          Semantics(
            selected: value == layout,
            inMutuallyExclusiveGroup: true,
            child: PlayraIconButton(
              tooltip: '${layout.label}布局',
              isSelected: value == layout,
              onPressed: () => onChanged(layout),

              icon: Icon(
                layout == CollectLayout.list
                    ? Icons.view_list_rounded
                    : Icons.grid_view_rounded,
              ),
            ),
          ),
      ],
    );
  }
}

class _CollectSortMenu extends StatelessWidget {
  const _CollectSortMenu({
    required this.value,
    required this.showLabel,
    required this.onChanged,
  });

  final CollectSort value;
  final bool showLabel;
  final ValueChanged<CollectSort> onChanged;

  @override
  Widget build(BuildContext context) {
    return KazumiMenuButton(
      menuChildren: [
        for (final sort in CollectSort.values)
          KazumiMenuItem(
            selected: value == sort,
            onPressed: () => onChanged(sort),
            label: sort.label,
          ),
      ],
      builder: (context, toggle) {
        return Tooltip(
          message: '排序：${value.label}',
          child: showLabel
              ? PlayraButton.ghostIcon(
                  onPressed: toggle,

                  icon: const Icon(Icons.sort_rounded, size: 20),
                  label: Text(value.label),
                )
              : PlayraIconButton(
                  onPressed: toggle,
                  icon: const Icon(Icons.sort_rounded),
                ),
        );
      },
    );
  }
}
