import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazumi/bean/dialog/dialog_helper.dart';
import 'package:kazumi/bean/settings/settings_detail_scaffold.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/network/proxy_utils.dart';
import 'package:kazumi/services/network/proxy_manager.dart';
import 'package:kazumi/request/core/dio_factory.dart';
import 'package:kazumi/request/core/network_config.dart';
import 'package:kazumi/bean/widget/tonal_card.dart';
import 'package:kazumi/bean/widget/state_presentation.dart';
import 'package:kazumi/pages/settings/sync/sync_settings_widgets.dart';
import 'package:kazumi/presentation/modern/settings/modern_settings_scope.dart';
import 'package:kazumi/presentation/modern/secondary/secondary_theme.dart';

class ProxyEditorPage extends StatefulWidget {
  const ProxyEditorPage({super.key});

  @override
  State<ProxyEditorPage> createState() => _ProxyEditorPageState();
}

class _ProxyEditorPageState extends State<ProxyEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController urlController = TextEditingController();
  final TextEditingController testUrlController = TextEditingController();
  bool _busy = false, _failed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    urlController.text = GStorage.getSetting(SettingsKeys.proxyUrl);
    testUrlController.text = GStorage.getSetting(SettingsKeys.proxyTestUrl);
  }

  @override
  void dispose() {
    urlController.dispose();
    testUrlController.dispose();
    super.dispose();
  }

  Future<void> saveAndTest() async {
    if (_busy || kIsWeb) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final url = urlController.text.trim();
    if (url.isEmpty) {
      KazumiDialog.showToast(message: '请输入代理地址');
      return;
    }

    final testUrl = testUrlController.text.trim().isEmpty
        ? 'https://www.google.com'
        : testUrlController.text.trim();

    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _failed = false;
      _message = '正在测试连接…';
    });
    try {
      await GStorage.putSetting(SettingsKeys.proxyUrl, url);
      await GStorage.putSetting(SettingsKeys.proxyTestUrl, testUrl);
      await GStorage.putSetting(SettingsKeys.proxyConfigured, false);
      await GStorage.putSetting(SettingsKeys.proxyEnable, true);
      ProxyManager.applyProxy();
      final parsed = ProxyUtils.parseProxyUrl(url);
      if (parsed == null) {
        throw StateError('Invalid proxy URL');
      }
      final dio = DioFactory.createForConfig(
        NetworkConfig(
          connectTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          proxyHost: parsed.$1,
          proxyPort: parsed.$2,
          allowBadCertificates: true,
          enableLog: false,
        ),
      );
      try {
        await dio.get(testUrl).timeout(const Duration(seconds: 15));
      } finally {
        dio.close();
      }
      await GStorage.putSetting(SettingsKeys.proxyConfigured, true);
      KazumiDialog.showToast(message: '测试成功');
      if (mounted) {
        setState(() => _message = '连接成功，代理已开启');
      }
    } catch (e) {
      await GStorage.putSetting(SettingsKeys.proxyEnable, false);
      ProxyManager.clearProxy();
      KazumiDialog.showToast(message: '代理连接失败');
      if (mounted) {
        setState(() {
          _failed = true;
          _message = '代理连接失败，请检查地址后重试';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return SettingsDetailScaffold(
        title: const Text('代理配置'),
        body: SecondaryFailureView(
          title: '浏览器代理由本地服务管理',
          message: '应用内代理配置仅适用于原生客户端。浏览器请通过启动服务的代理设置访问。',
          actionLabel: '返回网络设置',
          action: () => context.navigate('/settings/proxy'),
        ),
      );
    }
    final modern = ModernSettingsScope.isActiveOf(context);
    return SettingsDetailScaffold(
      title: const Text('代理配置'),
      body: modern
          ? SyncPageBody(
              children: [
                const SyncPageIntro(
                  icon: Icons.language_rounded,
                  title: '连接代理服务器',
                  description: '填写代理和测试地址，保存前会检查连接。',
                ),
                TonalCard(padding: const EdgeInsets.all(20), child: _form()),
                StateActionButton(
                  onPressed: _busy ? null : saveAndTest,
                  icon: Icons.save_outlined,
                  text: _busy ? '正在测试连接…' : '保存并测试',
                ),
                if (_message != null)
                  SyncFeedback(message: _message!, error: _failed, busy: _busy),
              ],
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: SizedBox(
                  width: (MediaQuery.of(context).size.width > 800) ? 800 : null,
                  child: _form(),
                ),
              ),
            ),
      floatingActionButton: modern
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : saveAndTest,
              icon: const Icon(Icons.save),
              label: Text(_busy ? '正在测试连接…' : '保存并测试'),
            ),
    );
  }

  Widget _form() => Form(
    key: _formKey,
    child: Column(
      children: [
        TextFormField(
          controller: urlController,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: '代理地址',
            hintText: 'http://127.0.0.1:7890',
            border: OutlineInputBorder(),
            errorMaxLines: 3,
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return '请输入代理地址';
            }
            if (!ProxyUtils.isValidProxyUrl(value)) {
              return '格式错误，请使用 http://host:port 格式';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: testUrlController,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => saveAndTest(),
          decoration: const InputDecoration(
            labelText: '测试地址',
            hintText: 'https://www.google.com',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    ),
  );
}
