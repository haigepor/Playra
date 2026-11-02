import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/storage.dart';
import 'package:kazumi/services/source/source_models.dart';
import 'package:kazumi/services/sync/bangumi_sync_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = BangumiSyncService();
  late Directory directory;
  late PathProviderPlatform original;
  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('playra-retired-sync-');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPaths(directory.path);
    Hive.init(directory.path);
    await GStorage.init();
  });
  setUp(() async {
    await GStorage.putSetting(SettingsKeys.bangumiAccessToken, 'saved-token');
    await GStorage.putSetting(SettingsKeys.bangumiSyncEnable, true);
  });
  tearDownAll(() async {
    await Hive.close();
    PathProviderPlatform.instance = original;
    expect(directory.parent.absolute.path, Directory.systemTemp.absolute.path);
    expect(
      directory.path.split(Platform.pathSeparator).last,
      startsWith('playra-retired-sync-'),
    );
    await directory.delete(recursive: true);
  });
  final removed = isA<SourceException>().having(
    (e) => e.code,
    'code',
    'SOURCE_REMOVED',
  );
  test(
    'retired synchronization never connects or replaces stored credentials',
    () async {
      await expectLater(service.ping(), throwsA(removed));
      await expectLater(service.saveToken('replacement'), throwsA(removed));
      expect(
        GStorage.getSetting(SettingsKeys.bangumiAccessToken),
        'saved-token',
      );
      expect(service.initialized, isFalse);
      expect(service.isConnecting, isFalse);
    },
  );
  test('old credentials cannot re-enable a removed source', () async {
    await service.setEnabled(false);
    await expectLater(service.setEnabled(true), throwsA(removed));
    expect(GStorage.getSetting(SettingsKeys.bangumiSyncEnable), isFalse);
    expect(GStorage.getSetting(SettingsKeys.bangumiAccessToken), 'saved-token');
  });
  test(
    'remote collection synchronization is rejected without local data mutation',
    () async {
      final before = GStorage.collectibles.length;
      expect(await service.syncCollectibleWhenIdle(1, 2), isFalse);
      await expectLater(service.syncCollectibles(), throwsA(removed));
      expect(GStorage.collectibles.length, before);
    },
  );
}

class _TestPaths extends PathProviderPlatform {
  _TestPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}
