/// 空壳项目保留的最小设置注册表。
///
/// 只保留播放器、主题、代理和更新所需键；收藏、历史、下载、同步、弹幕和
/// 内容源相关键随旧数据层一并移除。键名与旧版本保持一致，已安装用户升级后
/// 播放器偏好仍可读取。
enum SettingGroup { player, theme, proxy, update, misc }

class SettingContext {
  const SettingContext({this.compactLayout = false});

  final bool compactLayout;
}

class SettingKey<T> {
  const SettingKey(
    this.name,
    this.defaultValue, {
    required this.group,
    this.defaultResolver,
  });

  final String name;
  final T defaultValue;
  final SettingGroup group;
  final T Function(SettingContext context)? defaultResolver;

  T resolveDefault(SettingContext context) {
    return defaultResolver?.call(context) ?? defaultValue;
  }
}

class SettingsKeys {
  // 播放器
  static const hAenable = SettingKey<bool>(
    'hAenable',
    true,
    group: SettingGroup.player,
  );
  static const hardwareDecoder = SettingKey<String>(
    'hardwareDecoder',
    'auto-safe',
    group: SettingGroup.player,
  );
  static const androidEnableOpenSLES = SettingKey<bool>(
    'androidEnableOpenSLES',
    true,
    group: SettingGroup.player,
  );
  static const androidVideoRenderer = SettingKey<String>(
    'androidVideoRenderer',
    'auto',
    group: SettingGroup.player,
  );
  static const androidAutoEnterPIP = SettingKey<bool>(
    'androidAutoEnterPIP',
    false,
    group: SettingGroup.player,
  );
  static const defaultPlaySpeed = SettingKey<double>(
    'defaultPlaySpeed',
    1.0,
    group: SettingGroup.player,
  );
  static const defaultShortcutForwardPlaySpeed = SettingKey<double>(
    'defaultShortcutForwardPlaySpeed',
    2.0,
    group: SettingGroup.player,
  );
  static const defaultAspectRatioType = SettingKey<int>(
    'defaultAspectRatioType',
    1,
    group: SettingGroup.player,
  );
  static const buttonSkipTime = SettingKey<int>(
    'buttonSkipTime',
    80,
    group: SettingGroup.player,
  );
  static const arrowKeySkipTime = SettingKey<int>(
    'arrowKeySkipTime',
    10,
    group: SettingGroup.player,
  );
  static const autoPlay = SettingKey<bool>(
    'autoPlay',
    true,
    group: SettingGroup.player,
  );
  static const autoPlayNext = SettingKey<bool>(
    'autoPlayNext',
    true,
    group: SettingGroup.player,
  );
  static const playResume = SettingKey<bool>(
    'playResume',
    true,
    group: SettingGroup.player,
  );
  static const showPlayerError = SettingKey<bool>(
    'showPlayerError',
    false,
    group: SettingGroup.player,
  );
  static const privateMode = SettingKey<bool>(
    'privateMode',
    false,
    group: SettingGroup.player,
  );
  static const lowMemoryMode = SettingKey<bool>(
    'lowMemoryMode',
    false,
    group: SettingGroup.player,
  );
  static const lowMemoryPolicy = SettingKey<String?>(
    'lowMemoryPolicy',
    null,
    group: SettingGroup.player,
  );
  static const playerDebugMode = SettingKey<bool>(
    'playerDebugMode',
    false,
    group: SettingGroup.player,
  );
  static const playerLogLevel = SettingKey<int>(
    'playerLogLevel',
    2,
    group: SettingGroup.player,
  );
  static const playerMuted = SettingKey<bool>(
    'playerMuted',
    false,
    group: SettingGroup.player,
  );
  static const defaultVolume = SettingKey<double>(
    'defaultVolume',
    100.0,
    group: SettingGroup.player,
  );
  static const playerControllerLayerDisappearTime = SettingKey<int>(
    'playerControllerLayerDisappearTime',
    4000,
    group: SettingGroup.player,
  );
  static const backgroundPlayback = SettingKey<bool>(
    'backgroundPlayback',
    false,
    group: SettingGroup.player,
  );
  static const brightnessVolumeGesture = SettingKey<bool>(
    'brightnessVolumeGesture',
    true,
    group: SettingGroup.player,
  );
  static const playerDisableAnimations = SettingKey<bool>(
    'playerDisableAnimations',
    false,
    group: SettingGroup.player,
  );
  static const defaultSuperResolutionMode = SettingKey<int>(
    'defaultSuperResolutionType',
    1,
    group: SettingGroup.player,
  );
  static const disableSuperResolutionWarning = SettingKey<bool>(
    'superResolutionWarn',
    false,
    group: SettingGroup.player,
  );

  // 主题与界面
  static const themeMode = SettingKey<String>(
    'themeMode',
    'system',
    group: SettingGroup.theme,
  );
  static const themeColor = SettingKey<String>(
    'themeColor',
    'default',
    group: SettingGroup.theme,
  );
  static const useDynamicColor = SettingKey<bool>(
    'useDynamicColor',
    false,
    group: SettingGroup.theme,
  );
  static const useSystemFont = SettingKey<bool>(
    'useSystemFont',
    false,
    group: SettingGroup.theme,
  );
  static const oledEnhance = SettingKey<bool>(
    'oledEnhance',
    false,
    group: SettingGroup.theme,
  );
  static const showWindowButton = SettingKey<bool>(
    'showWindowButton',
    false,
    group: SettingGroup.theme,
  );
  static const displayMode = SettingKey<String?>(
    'displayMode',
    null,
    group: SettingGroup.misc,
  );
  static const exitBehavior = SettingKey<int>(
    'exitBehavior',
    2,
    group: SettingGroup.misc,
  );

  // 网络与更新
  static const enableGitProxy = SettingKey<bool>(
    'enableGitProxy',
    true,
    group: SettingGroup.proxy,
  );
  static const proxyEnable = SettingKey<bool>(
    'proxyEnable',
    false,
    group: SettingGroup.proxy,
  );
  static const proxyConfigured = SettingKey<bool>(
    'proxyConfigured',
    false,
    group: SettingGroup.proxy,
  );
  static const proxyUrl = SettingKey<String>(
    'proxyUrl',
    '',
    group: SettingGroup.proxy,
  );
  static const autoUpdate = SettingKey<bool>(
    'autoUpdate',
    true,
    group: SettingGroup.update,
  );

  static final List<SettingKey<dynamic>> all = [
    hAenable,
    hardwareDecoder,
    androidEnableOpenSLES,
    androidVideoRenderer,
    androidAutoEnterPIP,
    defaultPlaySpeed,
    defaultShortcutForwardPlaySpeed,
    defaultAspectRatioType,
    buttonSkipTime,
    arrowKeySkipTime,
    autoPlay,
    autoPlayNext,
    playResume,
    showPlayerError,
    privateMode,
    lowMemoryMode,
    lowMemoryPolicy,
    playerDebugMode,
    playerLogLevel,
    playerMuted,
    defaultVolume,
    playerControllerLayerDisappearTime,
    backgroundPlayback,
    brightnessVolumeGesture,
    playerDisableAnimations,
    defaultSuperResolutionMode,
    disableSuperResolutionWarning,
    themeMode,
    themeColor,
    useDynamicColor,
    useSystemFont,
    oledEnhance,
    showWindowButton,
    displayMode,
    exitBehavior,
    enableGitProxy,
    proxyEnable,
    proxyConfigured,
    proxyUrl,
    autoUpdate,
  ];
}
