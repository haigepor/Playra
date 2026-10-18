import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:kazumi/plugins/plugins.dart';
import 'package:kazumi/plugins/plugins_controller.dart';
import 'package:kazumi/services/source/source_policy.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Directory pluginDirectory;
  late File pluginsFile;
  late PathProviderPlatform previousPaths;

  Plugin bundled(String name) => Plugin.fromJson(
    jsonDecode(
      File('assets/plugins/$name.json').readAsStringSync(encoding: utf8),
    ),
  );

  Future<void> install(List<Plugin> plugins) async {
    await pluginsFile.writeAsString(
      jsonEncode(plugins.map((plugin) => plugin.toJson()).toList()),
      encoding: utf8,
    );
    await File('${pluginDirectory.path}/kazumi-v1.complete').writeAsString('1');
  }

  setUp(() async {
    previousPaths = PathProviderPlatform.instance;
    directory = await Directory.systemTemp.createTemp('playra-kazumi-startup-');
    PathProviderPlatform.instance = _Paths(directory.path);
    pluginDirectory = Directory('${directory.path}/plugins/v2');
    await pluginDirectory.create(recursive: true);
    pluginsFile = File('${pluginDirectory.path}/plugins.json');
    SourcePolicy.shared.persist = null;
    SourcePolicy.shared.environmentProvider = null;
    SourcePolicy.shared.restore('{}');
  });

  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    SourcePolicy.shared.persist = null;
    SourcePolicy.shared.environmentProvider = null;
    SourcePolicy.shared.restore('{}');
    expect(directory.parent.absolute.path, Directory.systemTemp.absolute.path);
    await directory.delete(recursive: true);
  });

  test('unchanged managed rules do not rewrite startup storage', () async {
    final aki = bundled('akianime')
      ..name = 'My anime'
      ..sourceId = 'kept-akianime';
    final mute = bundled('mutefun');
    final custom = bundled('AGE')
      ..baseUrl = 'https://custom.example/'
      ..sourceId = 'custom-age';
    final installed = [aki, mute, custom];
    await install(installed);
    SourcePolicy.shared.restore(
      jsonEncode({
        'preferences': {
          aki.providerId: {'enabled': false},
        },
      }),
    );
    final originalJson = await pluginsFile.readAsString(encoding: utf8);
    final writes = <String>[];
    final controller = PluginsController(
      pluginJsonWriter: (json) async => writes.add(json),
    );

    await controller.init();

    expect(writes, isEmpty);
    expect(
      controller.pluginList.map((p) => p.toJson()),
      installed.map((p) => p.toJson()),
    );
    expect(controller.pluginList.first.enabled, isFalse);
    expect(await pluginsFile.readAsString(encoding: utf8), originalJson);
    // Only the installed rules survive; deleted bundled entries stay deleted.
    expect(controller.pluginList, hasLength(3));
  });

  test(
    'a managed version update writes once and keeps its local identity',
    () async {
      final aki = bundled('akianime')
        ..version = '0.0.0'
        ..name = 'My anime'
        ..sourceId = 'kept-akianime';
      final mute = bundled('mutefun');
      await install([aki, mute]);
      final writes = <String>[];
      final controller = PluginsController(
        pluginJsonWriter: (json) async {
          writes.add(json);
          await pluginsFile.writeAsString(json, encoding: utf8);
        },
      );

      await controller.init();

      final updated = controller.pluginList.first;
      expect(updated.version, bundled('akianime').version);
      expect(updated.name, aki.name);
      expect(updated.providerId, aki.providerId);
      expect(controller.pluginList.last.toJson(), mute.toJson());
      expect(controller.pluginList, hasLength(2));
      expect(writes, hasLength(1));
      expect(
        (jsonDecode(writes.single) as List).first['sourceId'],
        aki.providerId,
      );

      await controller.init();

      expect(writes, hasLength(1));
      expect(controller.pluginList.first.toJson(), updated.toJson());
    },
  );

  test(
    'failed managed update restores all loaded rules and leaves disk intact',
    () async {
      final aki = bundled('akianime')
        ..version = '0.0.0'
        ..name = 'My anime'
        ..sourceId = 'kept-akianime';
      final mute = bundled('mutefun');
      final installed = [aki, mute];
      await install(installed);
      final originalJson = await pluginsFile.readAsString(encoding: utf8);
      var writes = 0;
      final controller = PluginsController(
        pluginJsonWriter: (_) async {
          writes++;
          throw StateError('write failed');
        },
        errorReporter: (_, _, _) {},
      );

      await expectLater(controller.init(), throwsStateError);

      expect(writes, 1);
      expect(
        controller.pluginList.map((p) => p.toJson()),
        installed.map((p) => p.toJson()),
      );
      expect(await pluginsFile.readAsString(encoding: utf8), originalJson);
      expect(
        await File('${pluginDirectory.path}/kazumi-v1.complete').exists(),
        isTrue,
      );
    },
  );
}
