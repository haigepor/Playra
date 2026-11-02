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
      File(
        'test/fixtures/retired_sources/plugins/$name.json',
      ).readAsStringSync(encoding: utf8),
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

  for (final version in ['1.0.0', '0.0.0']) {
    test(
      'retired rule version $version stays on disk without registration or updates',
      () async {
        final old = bundled('akianime')..version = version;
        await install([old]);
        final before = await pluginsFile.readAsBytes();
        var writes = 0;
        final controller = PluginsController(
          pluginJsonWriter: (_) async {
            writes++;
          },
        );
        await controller.init();
        await controller.init();
        expect(controller.pluginList, isEmpty);
        expect(controller.pluginHTTPList, isEmpty);
        expect(writes, 0);
        expect(await pluginsFile.readAsBytes(), before);
      },
    );
  }
  test('a legacy persistence failure cannot block Lumina startup', () async {
    await install([bundled('mutefun')]);
    final before = await pluginsFile.readAsBytes();
    final controller = PluginsController(
      pluginJsonWriter: (_) async {
        throw StateError('must not write');
      },
    );
    await controller.init();
    expect(controller.pluginList, isEmpty);
    expect(await pluginsFile.readAsBytes(), before);
  });
}
