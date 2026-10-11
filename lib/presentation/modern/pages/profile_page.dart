import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/pages/my/my_controller.dart';
import 'package:kazumi/request/config/api_endpoints.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:kazumi/presentation/shared/tab_shell.dart';
import '../home/home_theme.dart';
import '../profile/modern_profile_view.dart';
import '../profile/profile_sync_state.dart';

class ModernProfilePage extends StatefulWidget {
  const ModernProfilePage({
    super.key,
    required this.controller,
    this.readSyncState,
  });
  final MyController controller;
  final ProfileSyncState Function()? readSyncState;
  @override
  State<ModernProfilePage> createState() => _ModernProfilePageState();
}

class _ModernProfilePageState extends State<ModernProfilePage>
    with WidgetsBindingObserver {
  bool _attached = false;
  final _bangumi = BangumiSyncService();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bangumi.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setAttached(!RouteVisibility.isCoveredOf(context));
  }

  @override
  void didUpdateWidget(covariant ModernProfilePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attached && oldWidget.controller != widget.controller) {
      oldWidget.controller.detach();
      widget.controller.attach();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // 恢复时沿用共享控制器入口刷新，不新增持久订阅。
      if (_attached) {
        widget.controller.detach();
        widget.controller.attach();
      }
      _refresh();
    }
  }

  void _setAttached(bool value) {
    if (_attached == value) return;
    _attached = value;
    if (value) {
      widget.controller.attach();
    } else {
      widget.controller.detach();
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  ProfileSyncState _readSyncState() => ProfileSyncState.from(
    connecting: _bangumi.isConnecting,
    hasToken: GStorage.getSetting(
      SettingsKeys.bangumiAccessToken,
    ).trim().isNotEmpty,
    connectionError: _bangumi.lastError != null,
    verified: _bangumi.initialized,
    bangumiEnabled: GStorage.getSetting(SettingsKeys.bangumiSyncEnable),
    username: _bangumi.username,
    webDavConfigured: GStorage.getSetting(
      SettingsKeys.webDavURL,
    ).trim().isNotEmpty,
    webDavEnabled: GStorage.getSetting(SettingsKeys.webDavEnable),
    webDavHasContent:
        GStorage.getSetting(SettingsKeys.webDavEnableHistory) ||
        GStorage.getSetting(SettingsKeys.webDavEnableCollect) ||
        GStorage.getSetting(SettingsKeys.webDavEnableDanmakuShield),
  );
  @override
  void dispose() {
    _setAttached(false);
    _bangumi.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ModernHomeScope(
    child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: Observer(
          builder: (_) => ModernProfileView(
            stats: widget.controller.watchStats,
            sync: (widget.readSyncState ?? _readSyncState)(),
            version: ApiEndpoints.version,
            onOpen: (path) => context.pushNamed(path),
            onDiscover: () => TabDestinationScope.of(context)(0),
          ),
        ),
      ),
    ),
  );
}
