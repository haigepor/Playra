import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/modern/home/modern_home_controller.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_browse.dart';
import 'package:kazumi/presentation/modern/miomedia/miomedia_home_controller.dart';
import 'package:kazumi/services/source/miomedia/miomedia_service.dart';
import 'package:kazumi/services/source/source_models.dart';

void main() {
  test(
    'shared network failure stops four redundant discovery searches',
    () async {
      final operations = <String>[];
      final service = MioMediaService(
        request: (operation, _, _) async {
          operations.add(operation);
          throw const SourceException('UPSTREAM_UNAVAILABLE', 'private detail');
        },
      );
      final controller = MioHomeController(service);
      await controller.bootstrap();
      expect(controller.discoveryFailed, isTrue);
      expect(operations, unorderedEquals(['catalog', 'searchConfig']));
      expect(controller.failureCodes.values.toSet(), {'UPSTREAM_UNAVAILABLE'});
      expect(controller.failureMessage(MioKind.movie), contains('请检查网络'));
      expect(
        controller.failureMessage(MioKind.movie),
        isNot(contains('private')),
      );
      controller.dispose();
      service.dispose();
    },
  );

  test('retry clears failure after empty successful discovery', () async {
    var unavailable = true;
    final service = MioMediaService(
      request: (_, _, _) async {
        if (unavailable) {
          throw const SourceException('TIMEOUT', 'private timeout detail');
        }
        return {
          'data': {'videos': []},
        };
      },
    );
    final controller = MioHomeController(service);
    await controller.bootstrap();
    expect(controller.failureCodes[MioKind.movie], 'TIMEOUT');
    unavailable = false;
    await controller.bootstrap(force: true);
    expect(controller.discoveryFailed, isFalse);
    expect(controller.failed, isEmpty);
    expect(controller.failureCodes, isEmpty);
    controller.dispose();
    service.dispose();
  });

  test(
    'specific network and SDK failures stop repeated discovery with safe text',
    () async {
      final reasons = {
        'SDK_RESOURCE_MISSING': '内置 SDK 资源缺失',
        'UPSTREAM_PERMISSION_DENIED': '内容连接被系统拒绝',
        'UPSTREAM_NETWORK_UNREACHABLE': '当前网络无法到达内容服务',
        'UPSTREAM_CONNECTION_REFUSED': '内容服务拒绝连接',
        'UPSTREAM_CONNECTION_RESET': '内容服务连接中断',
        'UPSTREAM_DNS_ERROR': '内容服务地址解析失败',
      };
      for (final entry in reasons.entries) {
        final operations = <String>[];
        final service = MioMediaService(
          request: (operation, _, _) async {
            operations.add(operation);
            throw SourceException(entry.key, 'private exception text');
          },
        );
        final controller = MioHomeController(service);
        await controller.bootstrap();
        expect(operations, unorderedEquals(['catalog', 'searchConfig']));
        expect(controller.failureMessage(MioKind.movie), contains(entry.value));
        expect(
          controller.failureMessage(MioKind.movie),
          isNot(contains('private')),
        );
        controller.dispose();
        service.dispose();
      }
    },
  );

  test(
    'endpoint errors keep search fallback and category failure reason',
    () async {
      final operations = <String>[];
      final service = MioMediaService(
        request: (operation, _, _) async {
          operations.add(operation);
          throw const SourceException('UPSTREAM_NOT_FOUND', 'private endpoint');
        },
      );
      final controller = MioHomeController(service);
      await controller.bootstrap();
      expect(operations.where((value) => value == 'search'), hasLength(4));
      expect(controller.failureCodes[MioKind.movie], 'UPSTREAM_NOT_FOUND');
      controller.dispose();
      service.dispose();
    },
  );

  test('one working entry still discovers missing categories', () async {
    var searches = 0;
    final service = MioMediaService(
      request: (operation, _, _) async {
        if (operation == 'catalog') {
          throw const SourceException('UPSTREAM_UNAVAILABLE', 'private');
        }
        if (operation == 'search') searches++;
        return {
          'data': {'videos': []},
        };
      },
    );
    final controller = MioHomeController(service);
    await controller.bootstrap();
    expect(searches, 4);
    expect(controller.discoveryFailed, isFalse);
    controller.dispose();
    service.dispose();
  });

  test('known category retry clears local load failure', () async {
    var unavailable = true;
    final service = MioMediaService(
      request: (_, _, _) async {
        if (unavailable) {
          throw const SourceException('IDENTITY_ERROR', 'private identity');
        }
        return {
          'data': {'videos': []},
        };
      },
    );
    final controller = MioHomeController(service);
    controller.categoryIds[MioKind.movie] = '42';
    await controller.load(MioKind.movie, reset: true);
    expect(controller.failureMessage(MioKind.movie), contains('设备身份'));
    unavailable = false;
    await controller.load(MioKind.movie, reset: true);
    expect(controller.failed, isEmpty);
    expect(controller.failureCodes, isEmpty);
    controller.dispose();
    service.dispose();
  });

  testWidgets('home displays safe code without private exception details', (
    tester,
  ) async {
    final service = MioMediaService(
      request: (_, _, _) async {
        throw const SourceException('RUNTIME_UNAVAILABLE', 'private secret');
      },
    );
    final controller = MioHomeController(service);
    await controller.bootstrap();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MioHomeSections(
            controller: controller,
            feed: HomeFeed.movies,
            onDetails: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('内置 SDK 无法启动（RUNTIME_UNAVAILABLE）'), findsOneWidget);
    expect(find.textContaining('private secret'), findsNothing);
    expect(find.text('重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    service.dispose();
  });
}
