/// Private-build account maintenance, scheduled at application startup.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:synchronized/synchronized.dart';

import '../../../services/logging/logger.dart';
import '../../../services/storage/storage.dart';
import 'clicli_client.dart';
import 'clicli_maintenance.dart';

// Serializes maintenance in this application process. Do not run another
// account manager concurrently: Hive is not a cross-device order lock.
final Lock _maintenanceLock = Lock();

class _SettingsMaintenanceStore implements CliCliMaintenanceStore {
  _SettingsMaintenanceStore(String account)
    : _key = 'clicli.maintenance.${sha256.convert(utf8.encode(account))}';
  final String _key;

  @override
  Future<T> synchronized<T>(Future<T> Function() action) =>
      _maintenanceLock.synchronized(action);

  @override
  Future<CliCliMaintenanceRecord> read() async {
    final value = GStorage.settings.get(_key);
    if (value is! Map) return const CliCliMaintenanceRecord();
    return CliCliMaintenanceRecord(
      signedDay: value['signedDay'] as String?,
      watchProgressDay: value['watchProgressDay'] as String?,
      taskCompleteDay: value['taskCompleteDay'] as String?,
      renewedDay: value['renewedDay'] as String?,
      pendingOrder: value['pendingOrder'] == true,
    );
  }

  @override
  Future<void> write(CliCliMaintenanceRecord record) =>
      GStorage.settings.put(_key, <String, dynamic>{
        'signedDay': record.signedDay,
        'watchProgressDay': record.watchProgressDay,
        'taskCompleteDay': record.taskCompleteDay,
        'renewedDay': record.renewedDay,
        'pendingOrder': record.pendingOrder,
      });
}

Future<void> runCliCliMaintenance(CliCliClient client) async {
  if (!client.auth.configured) return;
  final maintenance = CliCliMaintenance(
    call: (path, body) async => <String, dynamic>{
      'code': 200,
      'data': await client.callData(path, body),
    },
    store: _SettingsMaintenanceStore(client.auth.account),
  );
  try {
    await client.auth.initialize();
  } catch (_) {
    KazumiLogger().w('CliCli: account login failed; maintenance skipped');
    return;
  }
  try {
    final coins = await maintenance.collectCoins();
    final gain = coins.detail['earned'];
    KazumiLogger().i('CliCli: daily coins ${coins.status} (+$gain)');
  } catch (_) {
    KazumiLogger().w('CliCli: coin collection failed; will retry on next launch');
  }
  try {
    final renewal = await maintenance.renew();
    KazumiLogger().i('CliCli: VIP maintenance ${renewal.status}');
    if (renewal.status == 'unconfirmedOrder') {
      KazumiLogger().w(
        'CliCli: order answered but expiry did not advance; '
        'blocked until reconciled',
      );
    }
  } catch (_) {
    KazumiLogger().w('CliCli: VIP maintenance failed; check account status');
  }
}
