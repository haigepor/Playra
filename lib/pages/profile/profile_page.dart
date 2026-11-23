import 'package:flutter/material.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:flutter/cupertino.dart'
    show CupertinoSlidingSegmentedControl, CupertinoSwitch;
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/discover/discover_page.dart';
import 'package:kazumi/pages/discover/home_layout.dart';
import 'package:kazumi/presentation/theme/playra_tokens.dart';
import 'package:kazumi/presentation/widgets/playra_backdrop.dart';
import 'package:kazumi/presentation/widgets/playra_page_header.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/services/storage/storage.dart';

/// “我的”页面：个人偏好、播放设置、网络代理与本地数据管理。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

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
  late bool _gestures;
  late bool _proxyEnable;
  late TextEditingController _proxyController;

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: PlayraBackdrop(
        child: SafeArea(
          bottom: false,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: layout.contentMaxWidth),
              child: Column(
                children: [
                  const PlayraPageHeader(title: '我的', largeTitle: true),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        layout.gutter,
                        0,
                        layout.gutter,
                        PlayraSpace.lg,
                      ),
                      children: [
                        _settingsSurface(
                          context,
                          child: ValueListenableBuilder<Box<dynamic>>(
                            valueListenable: HistoryStorage.listenable(),
                            builder: (context, box, _) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              minTileHeight: 48,
                              leading: const Icon(
                                Icons.history_rounded,
                                size: 22,
                              ),
                              title: const Text('播放历史'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (box.isNotEmpty)
                                    Text(
                                      '${box.length} 条',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.chevron_right_rounded,
                                    size: 18,
                                  ),
                                ],
                              ),
                              onTap: () => showPlaybackHistory(context),
                            ),
                          ),
                        ),
                        _settingsSurface(
                          context,
                          child: _buildAppearanceSection(context),
                        ),
                        _settingsSurface(
                          context,
                          child: _buildPlaybackSection(context),
                        ),
                        _settingsSurface(
                          context,
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.storage_rounded,
                              size: 22,
                            ),
                            title: const Text('网络与存储'),
                            children: [
                              if (!kIsWeb) _buildNetworkSection(context),
                              _buildStorageSection(context),
                            ],
                          ),
                        ),
                        _settingsSurface(
                          context,
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            leading: const Icon(
                              Icons.info_outline_rounded,
                              size: 22,
                            ),
                            title: const Text('关于 Playra'),
                            children: [
                              const ListTile(
                                contentPadding: EdgeInsets.zero,
                                minTileHeight: 48,
                                title: Text('开源许可'),
                                trailing: Text('GPL-3.0'),
                              ),
                              const ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text('播放内核'),
                                subtitle: Text('Kazumi · media_kit · MPV'),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                minTileHeight: 48,
                                title: const Text('HLS 播放演示'),
                                trailing: const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                ),
                                onTap: () => context.pushNamed('/player'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: PlayraSpace.section),
                      ],
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

  Widget _buildAppearanceSection(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final picker = CupertinoSlidingSegmentedControl<String>(
      groupValue: _themeMode,
      backgroundColor: colors.surfaceContainerHighest,
      thumbColor: colors.primaryContainer,
      children: {
        for (final (value, label) in const [
          ('system', '系统'),
          ('light', '浅色'),
          ('dark', '深色'),
        ])
          value: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _themeMode == value
                      ? colors.primary
                      : colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      },
      onValueChanged: (mode) {
        if (mode == null) return;
        setState(() => _themeMode = mode);
        GStorage.putSetting(SettingsKeys.themeMode, mode);
      },
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.palette_outlined, size: 22),
              SizedBox(width: 8),
              Text('外观', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          picker,
        ],
      ),
    );
  }

  Widget _settingsSurface(BuildContext context, {required Widget child}) {
    final t = PlayraTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: t.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: t.border.withValues(alpha: .65)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: child,
        ),
      ),
    );
  }

  Widget _playbackSwitch(String label, bool value, ValueChanged<bool> change) {
    return MergeSemantics(
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minTileHeight: 56,
        title: Text(label),
        onTap: () => change(!value),
        trailing: CupertinoSwitch(
          value: value,
          activeTrackColor: Theme.of(context).colorScheme.primary,
          onChanged: change,
        ),
      ),
    );
  }

  Widget _buildPlaybackSection(BuildContext context) {
    return _buildCard(
      context,
      title: '播放偏好',
      children: [
        _playbackSwitch('硬件解码', _hAenable, (val) {
          setState(() => _hAenable = val);
          GStorage.putSetting(SettingsKeys.hAenable, val);
        }),
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ListTile(
            contentPadding: EdgeInsets.zero,
            enabled: _hAenable,
            title: const Text('硬件解码方式'),
            subtitle: Text(switch (_hardwareDecoder) {
              'auto-safe' => '兼容优先（默认）',
              'mediacodec' => '性能优先',
              _ => '自定义：$_hardwareDecoder',
            }),
            trailing: const Icon(Icons.chevron_right_rounded, size: 18),
            onTap: _hAenable ? _chooseHardwareDecoder : null,
          ),
        _playbackSwitch('断点续播', _playResume, (val) {
          setState(() => _playResume = val);
          GStorage.putSetting(SettingsKeys.playResume, val);
        }),
        _playbackSwitch('自动下一集', _autoPlayNext, (val) {
          setState(() => _autoPlayNext = val);
          GStorage.putSetting(SettingsKeys.autoPlayNext, val);
        }),
        _playbackSwitch('音量与亮度手势', _gestures, (val) {
          setState(() => _gestures = val);
          GStorage.putSetting(SettingsKeys.brightnessVolumeGesture, val);
        }),
      ],
    );
  }

  Future<void> _chooseHardwareDecoder() async {
    final decoder = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('硬件解码方式'),
        children: [
          for (final (value, title, description) in const [
            ('auto-safe', '兼容优先（默认）', '自动选择兼容的硬件解码方式。'),
            ('mediacodec', '性能优先', '可改善部分旧设备的播放卡顿，部分视频色彩可能变化。'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, value),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(title),
                subtitle: Text(description),
                trailing: _hardwareDecoder == value
                    ? const Icon(Icons.check_rounded)
                    : null,
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
            child: Text('重新打开视频后生效。'),
          ),
        ],
      ),
    );
    if (decoder == null || !mounted) return;
    await GStorage.putSetting(SettingsKeys.hardwareDecoder, decoder);
    if (mounted) setState(() => _hardwareDecoder = decoder);
  }

  Widget _buildNetworkSection(BuildContext context) {
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
        _playbackSwitch('HTTP 代理', _proxyEnable, (enabled) {
          setState(() => _proxyEnable = enabled);
          GStorage.putSetting(SettingsKeys.proxyEnable, enabled);
          if (enabled) {
            ProxyManager.applyProxy();
          } else {
            ProxyManager.clearProxy();
          }
        }),
        if (_proxyEnable) ...[
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextField(
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
                  borderRadius: BorderRadius.circular(PlayraRadius.control),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: applyAddress, child: const Text('应用')),
          ),
        ],
      ],
    );
  }

  Widget _buildStorageSection(BuildContext context) {
    return _buildCard(
      context,
      title: '本地存储',
      children: [
        ValueListenableBuilder<Box<dynamic>>(
          valueListenable: HistoryStorage.listenable(),
          builder: (context, box, child) {
            final count = box.length;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              title: const Text('播放历史'),
              subtitle: count > 0 ? Text('$count 条') : null,
              trailing: count > 0
                  ? TextButton(
                      onPressed: () => confirmClearPlaybackHistory(context),
                      child: const Text('清空'),
                    )
                  : const Text('0 条'),
            );
          },
        ),
        ValueListenableBuilder<Box<dynamic>>(
          valueListenable: FavoriteStorage.listenable(),
          builder: (context, box, child) {
            final count = FavoriteStorage.getAll().length;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 48,
              title: const Text('追番'),
              trailing: Text('$count 部'),
            );
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          minTileHeight: 48,
          title: const Text('图片内存缓存'),
          trailing: TextButton(
            onPressed: () {
              PaintingBinding.instance.imageCache.clear();
              PaintingBinding.instance.imageCache.clearLiveImages();
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('图片内存缓存已清理')));
            },
            child: const Text('清理'),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final t = PlayraTokens.of(context);
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                0,
                PlayraSpace.sm,
                0,
                PlayraSpace.xs,
              ),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: PlayraType.body,
                  fontWeight: FontWeight.w700,
                  color: t.foreground,
                ),
              ),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
