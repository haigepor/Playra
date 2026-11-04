import 'package:kazumi/presentation/widgets/playra_controls.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_ui/shadcn_ui.dart' show LucideIcons;
import '../settings/modern_settings_scope.dart';

/// 只包住本轮新版二级页面；复用已有主题，不改变设置和主页面。
class ModernSecondaryScope extends StatelessWidget {
  const ModernSecondaryScope({super.key, required this.child});
  final Widget child;
  static bool isActiveOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_SecondaryAppearance>() !=
      null;
  @override
  Widget build(BuildContext context) =>
      ModernSettingsScope(child: _SecondaryAppearance(child: child));
}

class _SecondaryAppearance extends InheritedWidget {
  const _SecondaryAppearance({required super.child});
  @override
  bool updateShouldNotify(_SecondaryAppearance oldWidget) => false;
}

class SecondaryArtwork extends StatelessWidget {
  const SecondaryArtwork({super.key, required this.asset, this.width = 132});
  final String asset;
  final double width;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SvgPicture.asset(
      'assets/images/$asset.svg',
      width: width,
      height: width * .65,
      colorFilter: ColorFilter.mode(
        Theme.of(context).colorScheme.primary.withValues(alpha: .32),
        BlendMode.srcIn,
      ),
    ),
  );
}

class SecondaryEmptyState extends StatelessWidget {
  const SecondaryEmptyState({
    super.key,
    required this.title,
    this.description,
    this.asset = 'modern-search-empty',
    this.artwork,
    this.action,
  });
  final String title;
  final String? description;
  final String asset;
  final Widget? artwork;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        artwork ?? SecondaryArtwork(asset: asset),
        const SizedBox(height: 12),
        Semantics(
          header: true,
          liveRegion: true,
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (description != null) ...[
          const SizedBox(height: 8),
          Text(
            description!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 12), action!],
      ],
    ),
  );
}

/// 使用原生 TabBar，短线随点击滑动；外部选择变化不产生额外业务回调。
class SecondaryTabs extends StatefulWidget {
  const SecondaryTabs({
    super.key,
    required this.labels,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;
  final bool enabled;
  @override
  State<SecondaryTabs> createState() => _SecondaryTabsState();
}

class _SecondaryTabsState extends State<SecondaryTabs>
    with TickerProviderStateMixin {
  late TabController _tabs;
  Duration? _motionDuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final duration = PlayraMotion.duration(context, PlayraMotion.state);
    if (_motionDuration == duration) return;
    final index = _motionDuration == null ? widget.selected : _tabs.index;
    if (_motionDuration != null) _tabs.dispose();
    _motionDuration = duration;
    _tabs = TabController(
      length: widget.labels.length,
      initialIndex: index,
      vsync: this,
      animationDuration: duration,
    );
  }

  @override
  void didUpdateWidget(SecondaryTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_tabs.index != widget.selected) {
      _tabs.animateTo(widget.selected, duration: _motionDuration);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: !widget.enabled,
    child: IgnorePointer(
      ignoring: !widget.enabled,
      child: PlayraTabBar(
        controller: _tabs,
        onTap: widget.enabled ? widget.onChanged : null,

        tabs: [for (final label in widget.labels) Tab(height: 48, text: label)],
      ),
    ),
  );
}

class SecondaryFailureView extends StatelessWidget {
  const SecondaryFailureView({
    super.key,
    required this.title,
    required this.message,
    this.details,
    required this.action,
    this.actionLabel = '返回首页',
    this.actionIcon = LucideIcons.arrowLeft,
  });
  final String title;
  final String message;
  final String? details;
  final VoidCallback action;
  final String actionLabel;
  final IconData actionIcon;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                LucideIcons.circleAlert,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              Center(
                child: PlayraButton.icon(
                  onPressed: action,
                  icon: Icon(actionIcon, size: 18),
                  label: Text(actionLabel),
                ),
              ),
              if (details != null) ...[
                const SizedBox(height: 20),
                PlayraExpansionTile(
                  title: const Text('查看详细信息'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SelectableText(
                        details!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
