import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/features/sources/clicli/clicli_maintenance.dart';

class MemoryStore implements CliCliMaintenanceStore {
  CliCliMaintenanceRecord record = const CliCliMaintenanceRecord();
  Future<void> tail = Future.value();

  @override
  Future<T> synchronized<T>(Future<T> Function() action) {
    final result = tail.then((_) => action());
    tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<CliCliMaintenanceRecord> read() async => record;
  @override
  Future<void> write(CliCliMaintenanceRecord value) async => record = value;
}

void main() {
  late MemoryStore store;
  late DateTime now;
  late List<String> paths;
  late List<Map<String, dynamic>> orders;
  late Map<String, dynamic> info;
  late Map<String, dynamic> wallet;
  late Map<String, dynamic> plans;
  late Map<String, dynamic> Function() subscribe;
  late CliCliMaintenance service;

  /// Simulates the server advancing `expireTime` when an order succeeds, so the
  /// post-order confirmation has something real to check. Tests that assert the
  /// confirmation path should keep this enabled; tests that fake a no-op order
  /// return 200 without bumping the expiry.
  bool advanceExpiryOnOrder = true;

  setUp(() {
    store = MemoryStore();
    now = DateTime(2026, 1, 1, 12);
    paths = [];
    orders = [];
    info = {'isVip': true, 'expireTime': '2026-01-02T12:00:00'};
    wallet = {'coinBalance': 4500};
    plans = {
      'groups': [
        {
          'name': 'VIP',
          'plans': [
            {'id': 'week', 'status': 1, 'durationHours': 168, 'coinPrice': 100},
            {
              'id': 'month',
              'status': 1,
              'durationHours': 720,
              'coinPrice': 400,
            },
            {
              'id': 'year',
              'status': 1,
              'durationHours': 8760,
              'coinPrice': 4500,
            },
            {
              'id': 'disabled',
              'status': 0,
              'durationHours': 9999,
              'coinPrice': 1,
            },
            {'id': 'bad', 'status': 1, 'durationHours': 0, 'coinPrice': 1},
          ],
        },
        {
          'name': 'SVIP',
          'plans': [
            {'id': 'svip', 'durationHours': 8760, 'coinPrice': 1},
          ],
        },
      ],
    };
    subscribe = () => {'code': 200};
    service = CliCliMaintenance(
      store: store,
      now: () => now,
      isDefinitiveRejection: (response) => response['code'] == 4001,
      call: (path, body) async {
        paths.add(path);
        if (path.endsWith('/signIn'))
          return {
            'code': 200,
            'data': {'rewardAmount': 30},
          };
        if (path.endsWith('/wallet/info')) return {'code': 200, 'data': wallet};
        if (path.endsWith('/info')) return {'code': 200, 'data': info};
        if (path.endsWith('/plans')) return {'code': 200, 'data': plans};
        if (path.endsWith('/subscribe')) {
          orders.add(body);
          final result = subscribe();
          if (advanceExpiryOnOrder && result['code'] == 200) {
            // Mirror the live server: a real order moves the expiry forward.
            final before = DateTime.tryParse(
              (info['expireTime'] ?? '') as String? ?? '',
            );
            final added = body['planId'] == 'year'
                ? const Duration(hours: 8760)
                : body['planId'] == 'month'
                ? const Duration(hours: 720)
                : const Duration(hours: 168);
            final base = before ?? now;
            info['expireTime'] =
                '${base.add(added).toIso8601String().substring(0, 19)}';
          }
          return result;
        }
        throw StateError('Unexpected endpoint: $path');
      },
    );
  });

  test('signs once daily and never calls watch tasks', () async {
    expect((await service.signIn()).status, 'signed');
    expect((await service.signIn()).status, 'alreadySigned');
    now = now.add(const Duration(days: 1));
    expect((await service.signIn()).status, 'signed');
    expect(paths, everyElement(endsWith('/signIn')));
    expect(paths.length, 2);
  });

  test('48 hour boundary and dry-run do not subscribe', () async {
    info['expireTime'] = '2026-01-03T12:00:00';
    expect((await service.renew()).status, 'notDue');
    expect(paths.any((p) => p.endsWith('/plans')), isFalse);
    info['expireTime'] = '2026-01-03T11:59:59';
    final result = await service.renew(dryRun: true);
    expect(result.status, 'dryRun');
    expect(result.detail['planId'], 'year');
    expect(orders, isEmpty);
    expect(store.record.pendingOrder, isFalse);
  });

  test(
    'matches plan ratio and affordability, serializes duplicate calls',
    () async {
      wallet['coinBalance'] = 400;
      final results = await Future.wait([service.renew(), service.renew()]);
      expect(results.map((r) => r.status), ['renewed', 'alreadyRenewed']);
      expect(orders, [
        {'planId': 'month', 'payMethod': 3},
      ]);
    },
  );

  test('selects affordable shorter plan if none covers 168 hours', () async {
    plans = {
      'groups': [
        {
          'name': 'VIP',
          'plans': [
            {'id': 1, 'coinPrice': 10, 'durationHours': 24},
            {'id': 2, 'coinPrice': 30, 'durationHours': 100},
            {'id': 3, 'coinPrice': 101, 'durationHours': 168},
          ],
        },
      ],
    };
    wallet['coinBalance'] = 100;
    expect((await service.renew(dryRun: true)).detail['planId'], 2);
  });

  test(
    'known rejection retries, but ambiguous timeout blocks until reconciliation',
    () async {
      subscribe = () => {'code': 4001, 'msg': 'rejected'};
      expect((await service.renew()).status, 'failed');
      expect(store.record.pendingOrder, isFalse);
      subscribe = () => throw TimeoutException('unknown result');
      expect((await service.renew()).status, 'pendingOrder');
      expect((await service.renew()).status, 'pendingOrder');
      expect(orders.length, 2);
      await service.resolvePendingOrder(
        succeeded: false,
        orderDay: '2026-01-01',
      );
      subscribe = () => {'code': 200};
      expect((await service.renew()).status, 'renewed');
    },
  );

  test('unknown rejection stays pending by default', () async {
    final safeService = CliCliMaintenance(
      store: store,
      now: () => now,
      call: (path, body) async {
        if (path.endsWith('/wallet/info')) return {'code': 200, 'data': wallet};
        if (path.endsWith('/info')) return {'code': 200, 'data': info};
        if (path.endsWith('/plans')) return {'code': 200, 'data': plans};
        if (path.endsWith('/subscribe')) return {'code': 4001};
        throw StateError('Unexpected endpoint');
      },
    );
    expect((await safeService.renew()).status, 'pendingOrder');
    expect((await safeService.renew()).status, 'pendingOrder');
  });

  test('invalid account data never creates order', () async {
    info['expireTime'] = 'not a date';
    expect((await service.renew()).status, 'invalidExpiry');
    info['expireTime'] = null;
    expect((await service.renew()).status, 'invalidExpiry');
    info['isVip'] = false;
    wallet.remove('coinBalance');
    expect((await service.renew()).status, 'invalidBalance');
    expect(orders, isEmpty);
  });

  test('collects both daily sources and reports the real gain', () async {
    wallet['coinBalance'] = 10;
    final collecting = CliCliMaintenance(
      store: store,
      now: () => now,
      call: (path, body) async {
        paths.add(path);
        if (path.endsWith('/signIn')) {
          wallet['coinBalance'] = 40; // +30
          return {'code': 200};
        }
        if (path.endsWith('/task/watch-progress')) return {'code': 200};
        if (path.endsWith('/task/complete')) {
          wallet['coinBalance'] = 60; // +20
          return {'code': 200};
        }
        if (path.endsWith('/task/list')) {
          return {
            'code': 200,
            'data': {
              'tasks': [
                {'id': 'live-id', 'taskCode': 'watch_duration_reward'},
              ],
            },
          };
        }
        if (path.endsWith('/wallet/info'))
          return {'code': 200, 'data': wallet};
        if (path.endsWith('/info')) return {'code': 200, 'data': info};
        throw StateError('Unexpected endpoint: $path');
      },
    );
    final result = await collecting.collectCoins();
    expect(result.status, 'collected');
    expect(result.detail['earned'], 50);
    expect(result.detail['signInGain'], 30);
    expect(result.detail['durationGain'], 20);
    expect(store.record.signedDay, isNotNull);
    expect(store.record.taskCompleteDay, isNotNull);
    // A second run the same day must not repeat any request.
    final again = await collecting.collectCoins();
    expect(again.status, 'alreadyCollected');
  });

  test('gain is measured from the wallet, not the response body', () async {
    wallet['coinBalance'] = 0;
    final collecting = CliCliMaintenance(
      store: store,
      now: () => now,
      call: (path, body) async {
        // Sign-in succeeds but carries no rewardAmount — the live shape that
        // used to under-report the day by 30 coins.
        if (path.endsWith('/signIn')) {
          wallet['coinBalance'] = 30;
          return {'code': 200, 'data': {'success': true}};
        }
        if (path.endsWith('/wallet/info'))
          return {'code': 200, 'data': wallet};
        if (path.endsWith('/task/watch-progress')) return {'code': 400};
        if (path.endsWith('/task/complete')) return {'code': 400};
        if (path.endsWith('/task/list')) return {'code': 200, 'data': {}};
        if (path.endsWith('/info')) return {'code': 200, 'data': info};
        throw StateError('Unexpected endpoint: $path');
      },
    );
    final result = await collecting.collectCoins();
    expect(result.detail['signInGain'], 30);
    expect(result.detail['durationGain'], 0);
    expect(result.detail['earned'], 30);
  });

  test('an order that answers 200 without moving expiry stays pending', () async {
    info['expireTime'] = '2026-01-02T12:00:00';
    advanceExpiryOnOrder = false; // no-op order: the payMethod trap
    final result = await service.renew();
    expect(result.status, 'unconfirmedOrder');
    expect(store.record.pendingOrder, isTrue);
    expect(store.record.renewedDay, isNull);
    // Pending blocks the next attempt instead of retrying blindly.
    expect((await service.renew()).status, 'pendingOrder');
  });
}
