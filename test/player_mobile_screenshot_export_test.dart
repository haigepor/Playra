import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/player/controller/player_screenshot_controller.dart';
import 'package:kazumi/services/player/screenshot_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.fluttercandies/saver_gallery');
  const intentChannel = MethodChannel('com.predidit.kazumi/intent');
  const storageChannel = MethodChannel(
    'com.predidit.kazumi/download_directory',
  );
  const service = ScreenshotExportService();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(intentChannel, (call) async {
      expect(call.method, 'getAndroidSdkVersion');
      return 33;
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
    messenger.setMockMethodCallHandler(intentChannel, null);
    messenger.setMockMethodCallHandler(storageChannel, null);
  });

  Future<PlayerScreenshotController> selectedController() async {
    final controller = PlayerScreenshotController();
    addTearDown(controller.dispose);
    await controller.capture(
      capturePng: () async => Uint8List.fromList([1]),
      title: 'Title',
      episode: 'Episode',
      position: Duration.zero,
      isCurrent: () => true,
    );
    controller.setAllSelected(true);
    return controller;
  }

  Future<void> save(PlayerScreenshotController controller) => controller.save(
    chooseDestination: service.chooseDestination,
    write: service.write,
  );

  test('Android 28 requests storage permission before saving', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(intentChannel, (call) async {
      calls.add(call.method);
      return 28;
    });
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      calls.add(call.method);
      return true;
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return {'isSuccess': true};
    });
    final controller = await selectedController();
    await save(controller);
    expect(calls, [
      'getAndroidSdkVersion',
      'requestStorageAccess',
      'saveImageToGallery',
    ]);
    expect(controller.candidates, isEmpty);
    expect(controller.hasError, isFalse);
  });

  test('Android 28 denial retains selection and can be retried', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    var granted = false;
    var requests = 0;
    var writes = 0;
    messenger.setMockMethodCallHandler(intentChannel, (_) async => 28);
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      expect(call.method, 'requestStorageAccess');
      requests++;
      return granted;
    });
    messenger.setMockMethodCallHandler(channel, (_) async {
      writes++;
      return {'isSuccess': true};
    });
    final controller = await selectedController();
    await save(controller);
    expect(controller.hasError, isTrue);
    expect(controller.message, contains('请检查存储或相册权限后重试'));
    expect(controller.candidates, hasLength(1));
    expect(controller.selectedCount, 1);
    expect(writes, 0);
    granted = true;
    await save(controller);
    expect(requests, 2);
    expect(writes, 1);
    expect(controller.candidates, isEmpty);
    expect(controller.hasError, isFalse);
  });

  test(
    'legacy Android denial prompts only once for a selected batch',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var requests = 0;
      var writes = 0;
      messenger.setMockMethodCallHandler(intentChannel, (_) async => 28);
      messenger.setMockMethodCallHandler(storageChannel, (_) async {
        requests++;
        return false;
      });
      messenger.setMockMethodCallHandler(channel, (_) async {
        writes++;
        return {'isSuccess': true};
      });
      final controller = await selectedController();
      await controller.capture(
        capturePng: () async => Uint8List.fromList([2]),
        title: 'Title',
        episode: 'Episode',
        position: Duration.zero,
        isCurrent: () => true,
      );
      controller.setAllSelected(true);
      await save(controller);
      expect(requests, 1);
      expect(writes, 0);
      expect(controller.candidates, hasLength(2));
      expect(controller.selectedCount, 2);
      expect(controller.hasError, isTrue);
    },
  );

  for (final sdk in [29, 33]) {
    test('Android $sdk saves without requesting storage access', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var requests = 0;
      var writes = 0;
      messenger.setMockMethodCallHandler(intentChannel, (_) async => sdk);
      messenger.setMockMethodCallHandler(storageChannel, (_) async {
        requests++;
        return true;
      });
      messenger.setMockMethodCallHandler(channel, (_) async {
        writes++;
        return {'isSuccess': true};
      });
      final controller = await selectedController();
      await save(controller);
      expect(requests, 0);
      expect(writes, 1);
      expect(controller.candidates, isEmpty);
      expect(controller.hasError, isFalse);
    });
  }

  for (final sdk in <int?>[null, 0]) {
    test('invalid Android SDK $sdk never requests storage access', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var requests = 0;
      var writes = 0;
      messenger.setMockMethodCallHandler(intentChannel, (_) async => sdk);
      messenger.setMockMethodCallHandler(storageChannel, (_) async {
        requests++;
        return true;
      });
      messenger.setMockMethodCallHandler(channel, (_) async {
        writes++;
        return {'isSuccess': true};
      });
      final controller = await selectedController();
      await save(controller);
      expect(controller.hasError, isTrue);
      expect(controller.message, contains('重试'));
      expect(controller.candidates, hasLength(1));
      expect(controller.selectedCount, 1);
      expect(requests, 0);
      expect(writes, 0);
    });
  }

  test(
    'SDK query failure is retryable without requesting permission',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var fail = true;
      var requests = 0;
      var writes = 0;
      messenger.setMockMethodCallHandler(intentChannel, (_) async {
        if (fail) throw PlatformException(code: 'SDK_FAILED');
        return 33;
      });
      messenger.setMockMethodCallHandler(storageChannel, (_) async {
        requests++;
        return true;
      });
      messenger.setMockMethodCallHandler(channel, (_) async {
        writes++;
        return {'isSuccess': true};
      });
      final controller = await selectedController();
      await save(controller);
      expect(controller.hasError, isTrue);
      expect(controller.message, contains('重试'));
      expect(controller.candidates, hasLength(1));
      expect(controller.selectedCount, 1);
      expect(requests, 0);
      expect(writes, 0);
      fail = false;
      await save(controller);
      expect(requests, 0);
      expect(writes, 1);
      expect(controller.candidates, isEmpty);
      expect(controller.hasError, isFalse);
    },
  );

  test(
    'partial gallery failure retains only failed selection for retry',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(channel, (call) async {
        final image = call.arguments['image'] as Uint8List;
        return {'isSuccess': image.first == 1, 'errorMessage': 'write failed'};
      });
      final controller = PlayerScreenshotController();
      addTearDown(controller.dispose);
      for (final byte in [1, 2]) {
        await controller.capture(
          capturePng: () async => Uint8List.fromList([byte]),
          title: 'Title',
          episode: 'Episode',
          position: Duration.zero,
          isCurrent: () => true,
        );
      }
      controller.setAllSelected(true);
      await controller.save(
        chooseDestination: service.chooseDestination,
        write: service.write,
      );
      expect(controller.candidates, hasLength(1));
      expect(controller.candidates.single.bytes, Uint8List.fromList([2]));
      expect(controller.selectedCount, 1);
      expect(controller.message, contains('已保存 1 张，1 张失败'));
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      '$platform saves only selected candidates through native gallery and retries failure',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        final calls = <MethodCall>[];
        var fail = true;
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return {
            'isSuccess': !fail,
            'errorMessage': fail ? 'permission denied' : null,
          };
        });
        final controller = PlayerScreenshotController();
        addTearDown(controller.dispose);
        for (final byte in [1, 2]) {
          await controller.capture(
            capturePng: () async => Uint8List.fromList([byte]),
            title: 'Title',
            episode: 'Episode',
            position: Duration.zero,
            isCurrent: () => true,
          );
        }
        controller.toggle(controller.candidates.last);
        await controller.save(
          chooseDestination: service.chooseDestination,
          write: service.write,
        );
        expect(calls, hasLength(1));
        expect(calls.single.method, 'saveImageToGallery');
        expect(calls.single.arguments['image'], Uint8List.fromList([2]));
        expect(calls.single.arguments['skipIfExists'], false);
        expect(controller.hasError, isTrue);
        expect(controller.candidates, hasLength(2));
        expect(controller.selectedCount, 1);
        fail = false;
        await controller.save(
          chooseDestination: service.chooseDestination,
          write: service.write,
        );
        expect(calls, hasLength(2));
        expect(controller.candidates, hasLength(1));
        expect(controller.candidates.single.bytes, Uint8List.fromList([1]));
        expect(controller.selectedCount, 0);
        expect(controller.hasError, isFalse);
      },
    );
  }
}
