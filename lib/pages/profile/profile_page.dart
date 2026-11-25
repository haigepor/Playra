import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:kazumi/pages/discover/discover_page.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_home_tokens.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/storage/storage.dart';

/// “我的”页面 · 极简通透分层（方案 A）。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onOpenFavorites});

  final VoidCallback? onOpenFavorites;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? _proxyError;
  late String _themeMode;
  late bool _hAenable;
  late String _hardwareDecoder;
  late bool _playResume;
  late bool _autoPlayNext;
  late bool _backgroundPlayback;
  late bool _gestures;
  late bool _proxyEnable;
  late TextEditingController _proxyController;
  bool _networkExpanded = false;
  bool _aboutExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  void _loadSettings() {
    _themeMode = GStorage.getSetting(SettingsKeys.themeMode);
    _hAenable = GStorage.getSetting(SettingsKeys.hAenable);
    _hardwareDecoder = GStorage.getSetting(SettingsKeys.hardwareDecoder);
    _playResume = GStorage.getSetting(SettingsKeys.playResume);
    _autoPlayNext = GStorage.getSetting(SettingsKeys.autoPlayNext);
    _backgroundPlayback = GStorage.getSetting(SettingsKeys.backgroundPlayback);
    _gestures = GStorage.getSetting(SettingsKeys.brightnessVolumeGesture);
    _proxyEnable = GStorage.getSetting(SettingsKeys.proxyEnable);
    _proxyController = TextEditingController(
      text: GStorage.getSetting(SettingsKeys.proxyUrl),
    );
  }

  @override
  void dispose() {
    _proxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final layout = HomeLayoutMetrics.of(context);
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.paddingOf(context).bottom + PlayraSpace.lg;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayraBackdrop(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: isDark
                ? RadialGradient(
                    center: const Alignment(0.0, -1.15),
                    radius: 1.15,
                    colors: [
                      t.accent.withValues(alpha: 0.08),
                      t.pageBackground.withValues(alpha: 0.0),
                    ],
                  )
                : null,
          ),
          child: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
                child: Column(
                  children: [
                    const PlayraPageHeader(title: '我的', largeTitle: true),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.065)
                          : t.divider.withValues(alpha: 0.7),
                    ),
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.fromLTRB(
                          layout.gutter,
                          14,
                          layout.gutter,
                          bottomPad,
                        ),
                        children: [
                          _buildQuickStats(context),
                          const _SectionEyebrow(title: '外观'),
                          _ThemeSegmentedBar(
                            value: _themeMode,
                            onChanged: (value) {
                              if (_themeMode == value) return;
                              setState(() => _themeMode = value);
                              GStorage.putSetting(
                                SettingsKeys.themeMode,
                                value,
                              );
                            },
                          ),
                          const _SectionEyebrow(title: '播放设置'),
                          _buildPlaybackGroup(context),
                          const _SectionEyebrow(title: '系统与关于'),
                          _buildSystemGroup(context),
                          const SizedBox(height: PlayraSpace.md),
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
    );
  }

  Widget _buildQuickStats(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final favTint = isDark ? const Color(0xFF8AD8FF) : const Color(0xFF0284C7);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ValueListenableBuilder<Box<dynamic>>(
              valueListenable: HistoryStorage.listenable(),
              builder: (context, box, _) => _QuickAccessCard(
                icon: Icons.history_rounded,
                iconBg: t.accent.withValues(alpha: isDark ? 0.16 : 0.14),
                iconColor: t.accent,
                title: '播放历史',
                subtitle: box.isEmpty ? '暂无记录' : '${box.length} 条记录',
                onTap: () => showPlaybackHistory(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ValueListenableBuilder<Box<dynamic>>(
              valueListenable: FavoriteStorage.listenable(),
              builder: (context, box, _) {
                final count = FavoriteStorage.getAll().length;
                return _QuickAccessCard(
                  icon: Icons.bookmark_outline_rounded,
                  iconBg: favTint.withValues(alpha: isDark ? 0.14 : 0.12),
                  iconColor: favTint,
                  title: '本地追番',
                  subtitle: '$count 部作品',
                  onTap: widget.onOpenFavorites,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaybackGroup(BuildContext context) {
    final rows = <Widget>[
      _buildSwitchRow(
        context,
        icon: Icons.memory_rounded,
        accentIcon: true,
        label: '硬件解码',
        value: _hAenable,
        onChanged: (val) {
          setState(() => _hAenable = val);
          GStorage.putSetting(SettingsKeys.hAenable, val);
        },
      ),
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
        _buildActionRow(
          context,
          icon: Icons.tune_rounded,
          label: '硬件解码方式',
          subtitle: switch (_hardwareDecoder) {
            'auto-safe' => '兼容优先（默认）',
            'mediacodec' => '性能优先',
            _ => '自定义：$_hardwareDecoder',
          },
          enabled: _hAenable,
          onTap: _hAenable ? _chooseHardwareDecoder : null,
        ),
      _buildSwitchRow(
        context,
        icon: Icons.play_arrow_rounded,
        label: '断点续播',
        description: '下次播放时从上次退出的位置继续',
        value: _playResume,
        onChanged: (val) {
          setState(() => _playResume = val);
          GStorage.putSetting(SettingsKeys.playResume, val);
        },
      ),
      _buildSwitchRow(
        context,
        icon: Icons.skip_next_rounded,
        label: '自动下一集',
        description: '当前集播放结束后自动播放下一集',
        value: _autoPlayNext,
        onChanged: (val) {
          setState(() => _autoPlayNext = val);
          GStorage.putSetting(SettingsKeys.autoPlayNext, val);
        },
      ),
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS))
        _buildSwitchRow(
          context,
          icon: Icons.headphones_rounded,
          label: '后台播放',
          description: '切换到后台时继续播放，重新打开视频后生效',
          value: _backgroundPlayback,
          onChanged: (val) {
            setState(() => _backgroundPlayback = val);
            GStorage.putSetting(SettingsKeys.backgroundPlayback, val);
          },
        ),
      _buildSwitchRow(
        context,
        icon: Icons.touch_app_outlined,
        label: '音量与亮度手势',
        description: '在播放器中使用手势调节音量与亮度',
        value: _gestures,
        onChanged: (val) {
          setState(() => _gestures = val);
          GStorage.putSetting(SettingsKeys.brightnessVolumeGesture, val);
        },
      ),
    ];

    return _GroupedSurface(children: rows);
  }

  Widget _buildSystemGroup(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subPanelBg = isDark
        ? const Color(0xFF10141D)
        : const Color(0xFFF3F4F8);

    return _GroupedSurface(
      children: [
        Column(
          children: [
            _buildExpandHeader(
              context,
              icon: Icons.storage_rounded,
              title: '网络与存储',
              subtitle: 'HTTP 代理 · 缓存与本地数据',
              expanded: _networkExpanded,
              onTap: () => setState(() => _networkExpanded = !_networkExpanded),
            ),
            if (_networkExpanded) ...[
              Divider(height: 1, thickness: 1, color: t.divider),
              Material(
                color: subPanelBg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!kIsWeb) _buildNetworkSubPanel(context),
                    if (!kIsWeb)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 14,
                        endIndent: 14,
                        color: t.divider,
                      ),
                    _buildStorageSubPanel(context),
                  ],
                ),
              ),
            ],
          ],
        ),
        Column(
          children: [
            _buildExpandHeader(
              context,
              icon: Icons.info_outline_rounded,
              title: '关于 Playra',
              trailingText: 'GPL-3.0',
              expanded: _aboutExpanded,
              onTap: () => setState(() => _aboutExpanded = !_aboutExpanded),
            ),
            if (_aboutExpanded) ...[
              Divider(height: 1, thickness: 1, color: t.divider),
              Material(
                color: subPanelBg,
                child: Column(
                  children: [
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      minTileHeight: 44,
                      title: Text(
                        '开源许可',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      trailing: Text(
                        'GPL-3.0',
                        style: TextStyle(fontSize: 12.5, color: t.textSecondary),
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 14,
                      endIndent: 14,
                      color: t.divider,
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      minTileHeight: 48,
                      title: Text(
                        '播放内核',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        'Kazumi · media_kit · MPV',
                        style: TextStyle(fontSize: 11.5, color: t.textSecondary),
                      ),
                    ),
                    Divider(
                      height: 1,
                      thickness: 1,
                      indent: 14,
                      endIndent: 14,
                      color: t.divider,
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      minTileHeight: 44,
                      title: Text(
                        'HLS 播放演示',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: t.textSecondary.withValues(alpha: 0.7),
                      ),
                      onTap: () => context.pushNamed('/player'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ],
      dividerIndent: 52,
    );
  }

  Widget _buildExpandHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    String? trailingText,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
      minLeadingWidth: 28,
      horizontalTitleGap: 11,
      minTileHeight: 52,
      leading: _RowIconBadge(icon: icon, isDark: isDark, tokens: t),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: t.textPrimary,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              style: TextStyle(
                fontSize: 11.5,
                color: t.textSecondary.withValues(alpha: 0.8),
              ),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: TextStyle(
                fontSize: 12,
                color: t.textSecondary.withValues(alpha: 0.85),
              ),
            ),
            const SizedBox(width: 4),
          ],
          AnimatedRotation(
            turns: expanded ? 0.25 : 0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: t.textSecondary.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
    required IconData icon,
    bool accentIcon = false,
    required String label,
    String? description,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MergeSemantics(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
        minLeadingWidth: 28,
        horizontalTitleGap: 11,
        minTileHeight: 52,
        leading: _RowIconBadge(
          icon: icon,
          isDark: isDark,
          tokens: t,
          accent: accentIcon,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: t.textPrimary,
          ),
        ),
        subtitle: description == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  description,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: t.textSecondary.withValues(alpha: 0.82),
                  ),
                ),
              ),
        onTap: () => onChanged(!value),
        trailing: Transform.scale(
          scale: 0.78,
          alignment: Alignment.centerRight,
          child: CupertinoSwitch(
            value: value,
            activeTrackColor: t.accent,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  Widget _buildActionRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Opacity(
      opacity: enabled ? 1.0 : 0.44,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
        minLeadingWidth: 28,
        horizontalTitleGap: 11,
        minTileHeight: 52,
        enabled: enabled,
        leading: _RowIconBadge(icon: icon, isDark: isDark, tokens: t),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: t.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: t.textSecondary.withValues(alpha: 0.82),
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: t.textSecondary.withValues(alpha: 0.7),
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildNetworkSubPanel(BuildContext context) {
    final t = PlayraHomeTokens.of(context);

    void applyAddress() {
      final draft = _proxyController.text.trim();
      if (!ProxyUtils.isValidProxyUrl(draft)) {
        setState(() => _proxyError = '请输入主机:端口，端口范围 1–65535');
        return;
      }
      setState(() => _proxyError = null);
      GStorage.putSetting(SettingsKeys.proxyUrl, draft);
      ProxyManager.applyProxy();
      FocusScope.of(context).unfocus();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('代理地址已保存')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MergeSemantics(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            minTileHeight: 48,
            title: Text(
              'HTTP 代理',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
            onTap: () {
              final next = !_proxyEnable;
              setState(() => _proxyEnable = next);
              GStorage.putSetting(SettingsKeys.proxyEnable, next);
              if (next) {
                ProxyManager.applyProxy();
              } else {
                ProxyManager.clearProxy();
              }
            },
            trailing: Transform.scale(
              scale: 0.78,
              alignment: Alignment.centerRight,
              child: CupertinoSwitch(
                value: _proxyEnable,
                activeTrackColor: t.accent,
                onChanged: (enabled) {
                  setState(() => _proxyEnable = enabled);
                  GStorage.putSetting(SettingsKeys.proxyEnable, enabled);
                  if (enabled) {
                    ProxyManager.applyProxy();
                  } else {
                    ProxyManager.clearProxy();
                  }
                },
              ),
            ),
          ),
        ),
        if (_proxyEnable)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 2, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _proxyController,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => applyAddress(),
                  decoration: InputDecoration(
                    labelText: '代理地址',
                    hintText: '127.0.0.1:7890',
                    errorText: _proxyError,
                    errorMaxLines: 3,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: applyAddress,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('应用'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStorageSubPanel(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final errorColor = Theme.of(context).colorScheme.error;

    return Column(
      children: [
        ValueListenableBuilder<Box<dynamic>>(
          valueListenable: HistoryStorage.listenable(),
          builder: (context, box, _) {
            final count = box.length;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              minTileHeight: 46,
              title: Text(
                '播放历史',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
              subtitle: count > 0
                  ? Text(
                      '$count 条',
                      style: TextStyle(fontSize: 11.5, color: t.textSecondary),
                    )
                  : null,
              trailing: count > 0
                  ? TextButton(
                      onPressed: () => confirmClearPlaybackHistory(context),
                      style: TextButton.styleFrom(
                        foregroundColor: errorColor,
                        minimumSize: const Size(48, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      child: const Text('清空'),
                    )
                  : Text(
                      '0 条',
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
            );
          },
        ),
        Divider(
          height: 1,
          thickness: 1,
          indent: 14,
          endIndent: 14,
          color: t.divider,
        ),
        ValueListenableBuilder<Box<dynamic>>(
          valueListenable: FavoriteStorage.listenable(),
          builder: (context, box, _) {
            final count = FavoriteStorage.getAll().length;
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 2,
              ),
              minTileHeight: 44,
              title: Text(
                '追番',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: t.textPrimary,
                ),
              ),
              trailing: Text(
                '$count 部',
                style: TextStyle(fontSize: 12.5, color: t.textSecondary),
              ),
            );
          },
        ),
        Divider(
          height: 1,
          thickness: 1,
          indent: 14,
          endIndent: 14,
          color: t.divider,
        ),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 2,
          ),
          minTileHeight: 46,
          title: Text(
            '图片内存缓存',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: t.textPrimary,
            ),
          ),
          trailing: TextButton(
            onPressed: () {
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('图片内存缓存已清理')));
            },
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 34),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text('清理'),
          ),
        ),
      ],
    );
  }

  Future<void> _chooseHardwareDecoder() async {
    final decoder = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final t = PlayraHomeTokens.of(dialogContext);
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final dialogBg = isDark ? const Color(0xFF161B26) : Colors.white;
        final dialogBorder = isDark
            ? Colors.white.withValues(alpha: 0.09)
            : t.divider.withValues(alpha: 0.85);
        final idleOptionBg = isDark
            ? Colors.white.withValues(alpha: 0.038)
            : const Color(0xFFF5F6FA);
        final idleOptionBorder = isDark
            ? Colors.white.withValues(alpha: 0.07)
            : t.divider.withValues(alpha: 0.65);

        return SimpleDialog(
          backgroundColor: dialogBg,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: dialogBorder, width: 1),
          ),
          titlePadding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          contentPadding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: t.accent.withValues(alpha: isDark ? 0.16 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.tune_rounded, size: 16, color: t.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '硬件解码方式',
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          children: [
            for (final (value, title, description) in const [
              ('auto-safe', '兼容优先（默认）', '自动选择兼容的硬件解码方式。'),
              ('mediacodec', '性能优先', '可改善部分旧设备的播放卡顿，部分视频色彩可能变化。'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Builder(
                  builder: (context) {
                    final selected = _hardwareDecoder == value;
                    return Material(
                      color: selected
                          ? t.accent.withValues(alpha: isDark ? 0.14 : 0.10)
                          : idleOptionBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11),
                        side: BorderSide(
                          color: selected
                              ? t.accent.withValues(alpha: isDark ? 0.48 : 0.45)
                              : idleOptionBorder,
                          width: 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(11),
                        hoverColor: t.accent.withValues(alpha: 0.08),
                        splashColor: t.accent.withValues(alpha: 0.14),
                        onTap: () => Navigator.pop(dialogContext, value),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 13,
                            vertical: 11,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: selected
                                            ? FontWeight.w700
                                            : FontWeight.w600,
                                        color: selected
                                            ? t.accent
                                            : t.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      description,
                                      style: TextStyle(
                                        fontSize: 12,
                                        height: 1.4,
                                        color: t.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                selected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 20,
                                color: selected
                                    ? t.accent
                                    : t.textSecondary.withValues(alpha: 0.45),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: t.textSecondary.withValues(alpha: 0.72),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '重新打开视频后生效。',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: t.textSecondary.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
    if (decoder == null || !mounted) return;
    await GStorage.putSetting(SettingsKeys.hardwareDecoder, decoder);
    if (mounted) setState(() => _hardwareDecoder = decoder);
  }
}

class _SectionEyebrow extends StatelessWidget {
  const _SectionEyebrow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: t.textSecondary.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}

class _QuickAccessCard extends StatelessWidget {
  const _QuickAccessCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? t.cardSurface : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.075)
        : Colors.black.withValues(alpha: 0.065);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: cardBg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(color: borderColor, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          hoverColor: t.accent.withValues(alpha: 0.06),
          splashColor: t.accent.withValues(alpha: 0.12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: iconColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeSegmentedBar extends StatelessWidget {
  const _ThemeSegmentedBar({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _choices = [
    ('system', '跟随系统', Icons.computer_rounded),
    ('light', '浅色', Icons.light_mode_outlined),
    ('dark', '深色', Icons.dark_mode_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = PlayraMotion.reduceOf(context);
    final scaler = MediaQuery.textScalerOf(context);
    final selectedIndex = _choices
        .indexWhere((c) => c.$1 == value)
        .clamp(0, _choices.length - 1);

    final trackBg = isDark ? t.cardSurface : Colors.white;
    final trackBorder = isDark
        ? Colors.white.withValues(alpha: 0.075)
        : Colors.black.withValues(alpha: 0.065);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: trackBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: trackBorder, width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / _choices.length;
          final stacked = cellWidth < 104 || scaler.scale(12.5) > 17;
          final segHeight = stacked
              ? (scaler.scale(12) * 2.2 + 28).clamp(56.0, double.infinity)
              : 38.0;

          return SizedBox(
            height: segHeight,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: selectedIndex * cellWidth,
                  top: 0,
                  bottom: 0,
                  width: cellWidth,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.accent.withValues(alpha: isDark ? 0.18 : 0.14),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(
                          color: t.accent.withValues(
                            alpha: isDark ? 0.34 : 0.30,
                          ),
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final (choiceValue, label, icon) in _choices)
                      Expanded(
                        child: _ThemeSegmentItem(
                          label: label,
                          icon: icon,
                          selected: choiceValue == value,
                          stacked: stacked,
                          activeColor: t.accent,
                          inactiveColor: t.textSecondary,
                          onTap: () => onChanged(choiceValue),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ThemeSegmentItem extends StatelessWidget {
  const _ThemeSegmentItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.stacked,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool stacked;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected ? activeColor : inactiveColor;
    final textStyle = TextStyle(
      fontSize: 12.5,
      height: 1.15,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      color: fg,
    );

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: stacked
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: fg),
                        const SizedBox(height: 2),
                        Text(
                          label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: textStyle,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: fg),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupedSurface extends StatelessWidget {
  const _GroupedSurface({required this.children, this.dividerIndent = 52});

  final List<Widget> children;
  final double dividerIndent;

  @override
  Widget build(BuildContext context) {
    final t = PlayraHomeTokens.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? t.cardSurface : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.075)
        : Colors.black.withValues(alpha: 0.065);
    final innerDivider = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : t.divider.withValues(alpha: 0.6);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.035),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: dividerIndent,
                  endIndent: 13,
                  color: innerDivider,
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _RowIconBadge extends StatelessWidget {
  const _RowIconBadge({
    required this.icon,
    required this.isDark,
    required this.tokens,
    this.accent = false,
  });

  final IconData icon;
  final bool isDark;
  final PlayraHomeTokens tokens;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final bg = accent
        ? tokens.accent.withValues(alpha: isDark ? 0.16 : 0.12)
        : (isDark
              ? const Color(0xFF1F2636)
              : const Color(0xFFF1EFF8));
    final fg = accent ? tokens.accent : tokens.textSecondary;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 16, color: fg),
    );
  }
}
