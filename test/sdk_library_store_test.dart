import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/source/sdk_playback_models.dart';
import 'package:kazumi/services/storage/sdk_library_store.dart';

void main() {
  late Directory directory;
  late Box<String> box;
  late SdkLibraryStore store;
  var private = false;
  const video = SdkVideoData(id: '42', title: '同名作品');
  const episode = SdkEpisode(
    number: null,
    name: 'SP 上篇',
    code: 'mp4',
    reference: 'SP 上篇',
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sdk-library-test');
    Hive.init(directory.path);
    box = await Hive.openBox<String>('sdk-personal');
    private = false;
    store = SdkLibraryStore(box: box, privateMode: () => private);
  });
  tearDown(() async {
    store.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
  Future<void> watch(String provider, {int seconds = 38}) => store.record(
    providerId: provider,
    video: video,
    episode: episode,
    position: Duration(seconds: seconds),
    duration: const Duration(minutes: 20),
    automatic: false,
    qualityCode: '2160p',
  );
  test(
    'same content id stays isolated, special part and locks survive reopen',
    () async {
      await watch('lumina');
      await watch('miomedia', seconds: 9);
      store.dispose();
      await box.close();
      box = await Hive.openBox<String>('sdk-personal');
      store = SdkLibraryStore(box: box, privateMode: () => private);
      expect(store.histories.length, 2);
      final progress = store.get('lumina', '42')!.lastWatch!;
      expect(progress.episode.reference, 'SP 上篇');
      expect(progress.episode.number, isNull);
      expect(progress.position.inSeconds, 38);
      expect(progress.automatic, isFalse);
      expect(progress.qualityCode, '2160p');
      expect(store.get('miomedia', '42')!.lastWatch!.position.inSeconds, 9);
    },
  );
  test('collection and history deletion are independent', () async {
    await store.collect(providerId: 'lumina', video: video, type: 2);
    expect(store.histories, isEmpty);
    await watch('lumina');
    await store.deleteHistory('lumina', '42');
    expect(store.collections.single.collectionType, 2);
    await watch('lumina');
    await store.collect(providerId: 'lumina', video: video, type: 0);
    expect(store.collections, isEmpty);
    expect(store.histories.single.lastWatch!.position.inSeconds, 38);
  });
  test(
    'private mode stops history writes but permits deliberate collection',
    () async {
      private = true;
      await watch('lumina');
      expect(store.histories, isEmpty);
      await store.collect(providerId: 'lumina', video: video, type: 1);
      expect(store.collections.length, 1);
      expect(store.histories, isEmpty);
    },
  );
  test(
    'serialized writes retain collection and both episode progress records',
    () async {
      await Future.wait([
        watch('lumina'),
        store.collect(providerId: 'lumina', video: video, type: 1),
        store.record(
          providerId: 'lumina',
          video: video,
          episode: const SdkEpisode(
            number: 99,
            name: '第99集',
            code: 'mp4',
            reference: '第99集',
          ),
          position: const Duration(seconds: 55),
          duration: const Duration(minutes: 20),
          automatic: true,
        ),
      ]);
      final record = store.get('lumina', '42')!;
      expect(record.progresses.length, 2);
      expect(record.collectionType, 1);
      expect(record.lastWatch!.episode.number, 99);
      await store.clearHistory();
      expect(store.histories, isEmpty);
      expect(store.collections.length, 1);
    },
  );
  test(
    'failed mutation permits later retry and private mode is read on each write',
    () async {
      await expectLater(
        store.collect(providerId: 'lumina', video: video, type: 9),
        throwsArgumentError,
      );
      await store.collect(providerId: 'lumina', video: video, type: 1);
      await watch('lumina');
      private = true;
      await watch('lumina', seconds: 99);
      expect(store.histories.single.lastWatch!.position.inSeconds, 38);
      private = false;
      await watch('lumina', seconds: 99);
      expect(store.histories.single.lastWatch!.position.inSeconds, 99);
      expect(store.collections.single.collectionType, 1);
    },
  );
  test(
    'corrupt record does not hide valid records; unknown fields are not persisted',
    () async {
      await box.put('bad', '{');
      await watch('lumina');
      expect(store.histories.length, 1);
      final raw = jsonDecode(box.get(jsonEncode(['lumina', '42']))!) as Map;
      expect(raw.containsKey('media'), isFalse);
      expect(raw.containsKey('headers'), isFalse);
      expect(raw['schemaVersion'], 1);
    },
  );
}
