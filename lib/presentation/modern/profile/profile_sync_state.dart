/// 仅表达已知配置和已验证连接，不把配置存在当成同步成功。
class ProfileSyncState {
  const ProfileSyncState({
    required this.bangumi,
    required this.webDav,
    this.username = '',
  });
  final String bangumi;
  final String webDav;
  final String username;

  factory ProfileSyncState.from({
    required bool connecting,
    required bool hasToken,
    required bool connectionError,
    required bool verified,
    required bool bangumiEnabled,
    required String username,
    required bool webDavConfigured,
    required bool webDavEnabled,
    required bool webDavHasContent,
  }) => ProfileSyncState(
    bangumi: connecting
        ? '正在验证连接'
        : !hasToken
        ? '未连接 · 连接后可同步追番'
        : connectionError
        ? '连接异常 · 点击检查'
        : !verified
        ? '待验证 · 打开设置检查连接'
        : !bangumiEnabled
        ? '已连接 · 同步关闭'
        : '已连接 · 追番同步已开启',
    username: verified && hasToken && !connecting && !connectionError
        ? username
        : '',
    webDav: !webDavConfigured
        ? '未配置'
        : !webDavEnabled
        ? '已配置 · 同步关闭'
        : !webDavHasContent
        ? '待选择同步内容'
        : '已开启 · 查看同步设置',
  );
}
