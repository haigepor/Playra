/// Account-scoped daily coin collection and coin-funded VIP maintenance.
///
/// Authentication and transport are supplied by the caller. This module does
/// not schedule itself and never reports fabricated viewing progress.
///
/// Daily income has two sources, both server-limited to once per day:
///   * `signIn`                 +30 coins, no precondition
///   * `watch_duration_reward`  +20 coins, needs one progress record first
/// Together that is 50 coins/day, which covers a 7-day plan (100 coins) every
/// other day — enough to keep VIP alive indefinitely.
library;

import 'dart:math';

typedef CliCliMaintenanceCall =
    Future<Map<String, dynamic>> Function(
      String path,
      Map<String, dynamic> body,
    );

/// Persistent record for one account. A pending order is deliberately not
/// cleared automatically: its outcome may have been lost after dispatch.
class CliCliMaintenanceRecord {
  const CliCliMaintenanceRecord({
    this.signedDay,
    this.watchProgressDay,
    this.taskCompleteDay,
    this.renewedDay,
    this.pendingOrder = false,
  });
  final String? signedDay;
  final String? watchProgressDay;
  final String? taskCompleteDay;
  final String? renewedDay;
  final bool pendingOrder;
}

/// Implementations must be durable, scoped to one account, and serialize the
/// whole callback across all users/processes of that account. [write] must
/// persist before completing; in particular, a pending order must survive a
/// crash before the subscribe request is sent.
abstract class CliCliMaintenanceStore {
  Future<T> synchronized<T>(Future<T> Function() action);
  Future<CliCliMaintenanceRecord> read();
  Future<void> write(CliCliMaintenanceRecord record);
}

class CliCliMaintenanceResult {
  const CliCliMaintenanceResult(this.status, {this.detail = const {}});
  final String status;
  final Map<String, dynamic> detail;
}

class CliCliMaintenance {
  CliCliMaintenance({
    required this.call,
    required this.store,
    this.isDefinitiveRejection,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final CliCliMaintenanceCall call;
  final CliCliMaintenanceStore store;

  /// Opt in only for response codes independently known to mean no order was
  /// created. The safe default treats every non-success as ambiguous.
  final bool Function(Map<String, dynamic>)? isDefinitiveRejection;
  final DateTime Function() _now;

  static const _base = '/api/v1/app/client/vipCenter';
  static const _durationTaskCode = 'watch_duration_reward';

  /// Fallback id for the viewing task. The live id is read from `task/list`
  /// first; this value only matters if that endpoint is unavailable, and the
  /// server can resolve the task from `taskCode` alone.
  static const _durationTaskFallbackId = '346506380267249664';

  /// Renew at or below this many hours remaining.
  static const _renewThresholdHours = 48.0;

  /// Try to leave at least this much membership after one order.
  static const _renewTargetHours = 144.0;

  String _day(DateTime now) {
    final chinaTime = now.toUtc().add(const Duration(hours: 8));
    return '${chinaTime.year.toString().padLeft(4, '0')}-'
        '${chinaTime.month.toString().padLeft(2, '0')}-${chinaTime.day.toString().padLeft(2, '0')}';
  }

  /// Collects both daily coin sources and reports the real gain.
  ///
  /// Earnings are measured by comparing wallet balances before and after, not
  /// by reading `data.rewardAmount`: a successful sign-in does not always carry
  /// that field, and trusting it silently under-reports the day by 30 coins.
  ///
  /// The viewing task does not validate elapsed watch time server-side — the
  /// task description says 60 minutes, but a completion request succeeds with a
  /// few seconds recorded. A minimal progress report is still sent first so the
  /// day has a record, and it is never inflated. Both sources are capped at once
  /// per day server-side, so a second run reports `alreadyCollected`.
  Future<CliCliMaintenanceResult> collectCoins() =>
      store.synchronized(() async {
        final day = _day(_now());
        final record = await store.read();
        if (record.signedDay == day && record.taskCompleteDay == day) {
          return const CliCliMaintenanceResult('alreadyCollected');
        }
        final before = await _coinBalance();
        if (before == null) return const CliCliMaintenanceResult('failed');

        final detail = <String, dynamic>{'balanceBefore': before};

        // Source 1 — daily sign-in (+30).
        Map<String, dynamic> signIn = const {};
        if (record.signedDay != day) {
          signIn = await call('$_base/signIn', <String, dynamic>{});
          detail['signIn'] = {
            'code': signIn['code'],
            'msg': signIn['msg'],
          };
        } else {
          detail['signIn'] = const {'code': null, 'msg': 'alreadySigned'};
        }
        final afterSignIn = await _coinBalance();
        detail['signInGain'] = _gain(before, afterSignIn);

        // Source 2 — viewing task (+20). Needs one progress record, then the
        // completion call. No viewing duration is fabricated.
        Map<String, dynamic> complete = const {};
        if (record.taskCompleteDay != day) {
          final taskId = await _durationTaskId();
          await call('$_base/task/watch-progress', <String, dynamic>{
            'taskCode': _durationTaskCode,
            'sessionId': _hexToken(16),
            'reportId': _hexToken(16),
            'deltaSeconds': 1,
          });
          complete = await call('$_base/task/complete', <String, dynamic>{
            'taskCode': _durationTaskCode,
            'nonce': null,
            'taskId': taskId,
          });
          detail['duration'] = {
            'code': complete['code'],
            'msg': complete['msg'],
          };
        } else {
          detail['duration'] = const {'code': null, 'msg': 'alreadyCompleted'};
        }
        final afterTask = await _coinBalance();
        detail['durationGain'] = _gain(afterSignIn, afterTask);

        final earned =
            (afterTask != null ? afterTask - before : 0).clamp(0, 1 << 30);
        detail['earned'] = earned;
        detail['balanceAfter'] = afterTask;

        // Record the day only for sources the server actually accepted, so a
        // transport failure can be retried on the next launch.
        final signedToday =
            record.signedDay == day || _succeeded(signIn);
        final completedToday =
            record.taskCompleteDay == day || _succeeded(complete);
        if (signedToday || completedToday) {
          await store.write(
            CliCliMaintenanceRecord(
              signedDay: signedToday ? day : record.signedDay,
              watchProgressDay: record.watchProgressDay,
              taskCompleteDay: completedToday ? day : record.taskCompleteDay,
              renewedDay: record.renewedDay,
              pendingOrder: record.pendingOrder,
            ),
          );
        }
        return CliCliMaintenanceResult(
          earned > 0 ? 'collected' : 'noGain',
          detail: detail,
        );
      });

  /// Sign-in only. Kept for callers that do not want the viewing task.
  ///
  /// Successful sign-ins are recorded by local calendar day. Transport or API
  /// failures are not recorded and may be retried. The server remains the
  /// authority on its own day boundary and already-signed responses.
  Future<CliCliMaintenanceResult> signIn() => store.synchronized(() async {
    final day = _day(_now());
    final record = await store.read();
    if (record.signedDay == day)
      return const CliCliMaintenanceResult('alreadySigned');
    final response = await call('$_base/signIn', <String, dynamic>{});
    if (response['code'] != 200) {
      return CliCliMaintenanceResult('failed', detail: response);
    }
    await store.write(
      CliCliMaintenanceRecord(
        signedDay: day,
        watchProgressDay: record.watchProgressDay,
        taskCompleteDay: record.taskCompleteDay,
        renewedDay: record.renewedDay,
        pendingOrder: record.pendingOrder,
      ),
    );
    return CliCliMaintenanceResult('signed', detail: response);
  });

  /// Current coin balance, or null when it cannot be read. Never returns 0 as a
  /// substitute: a failed read would then look like a spent balance.
  Future<int?> _coinBalance() async {
    final wallet = _data(await call('$_base/wallet/info', <String, dynamic>{}));
    final value = wallet == null ? null : _integer(wallet['coinBalance']);
    if (value != null) return value;
    final info = _data(await call('$_base/info', <String, dynamic>{}));
    return info == null ? null : _integer(info['coinBalance']);
  }

  /// Live id of the viewing task, falling back to the known default.
  Future<String> _durationTaskId() async {
    try {
      final data = _data(await call('$_base/task/list', <String, dynamic>{}));
      final tasks = data?['tasks'];
      if (tasks is List) {
        for (final task in tasks) {
          if (task is Map && task['taskCode'] == _durationTaskCode) {
            final id = task['id'];
            if (id != null && id.toString().isNotEmpty) return id.toString();
          }
        }
      }
    } catch (_) {
      // Fall through to the default id.
    }
    return _durationTaskFallbackId;
  }

  /// True when the membership expiry actually moved forward after an order.
  Future<bool> _confirmRenewal(DateTime? before) async {
    try {
      final info = _data(await call('$_base/info', <String, dynamic>{}));
      final raw = info?['expireTime'];
      if (raw is! String || raw.isEmpty) return false;
      final after = DateTime.tryParse(raw);
      if (after == null) return false;
      if (before == null) return info?['isVip'] == true;
      return after.isAfter(before);
    } catch (_) {
      return false;
    }
  }

  int _gain(int? from, int? to) =>
      (from == null || to == null) ? 0 : (to - from).clamp(0, 1 << 30);

  bool _succeeded(Map<String, dynamic> response) => response['code'] == 200;

  String _hexToken(int byteCount) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < byteCount; i++) {
      buffer.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Renews only with <48 hours remaining. Pass dryRun to inspect the decision
  /// without writing a pending order or calling subscribe. Ambiguous subscribe
  /// errors block future orders until explicitly reconciled by the caller.
  Future<CliCliMaintenanceResult> renew({
    bool dryRun = false,
  }) => store.synchronized(() async {
    final record = await store.read();
    if (record.pendingOrder)
      return const CliCliMaintenanceResult('pendingOrder');
    final now = _now();
    final day = _day(now);
    if (record.renewedDay == day)
      return const CliCliMaintenanceResult('alreadyRenewed');
    final info = _data(await call('$_base/info', <String, dynamic>{}));
    final wallet = _data(await call('$_base/wallet/info', <String, dynamic>{}));
    if (info == null || wallet == null)
      return const CliCliMaintenanceResult('failed');
    final dynamic rawExpire = info['expireTime'];
    DateTime? expiry;
    if (rawExpire is String && rawExpire.isNotEmpty) {
      expiry = DateTime.tryParse(rawExpire);
      if (expiry == null) return const CliCliMaintenanceResult('invalidExpiry');
    } else if (rawExpire != null && rawExpire != '') {
      return const CliCliMaintenanceResult('invalidExpiry');
    } else if (info['isVip'] != false) {
      // A missing expiration on an active or unknown membership is unsafe.
      return const CliCliMaintenanceResult('invalidExpiry');
    }
    final remaining = expiry == null
        ? 0.0
        : expiry.difference(now).inMicroseconds / Duration.microsecondsPerHour;
    if (remaining >= _renewThresholdHours)
      return CliCliMaintenanceResult(
        'notDue',
        detail: {'remainingHours': remaining},
      );
    final balance = _integer(wallet['coinBalance']);
    if (balance == null || balance < 0)
      return const CliCliMaintenanceResult('invalidBalance');
    final plans = _data(await call('$_base/plans', <String, dynamic>{}));
    if (plans == null || plans['groups'] is! List)
      return const CliCliMaintenanceResult('failed');
    // Prefer a plan that covers the gap up to the target, but never aim below
    // one week: a shorter order would just trigger again immediately.
    final gap = _renewTargetHours - (remaining > 0 ? remaining : 0);
    final need = gap < 168 ? 168.0 : gap;
    // The reference normalizes VIP plans by duration; later entries replace
    // earlier entries with the same duration before affordability is checked.
    final byDuration = <int, _Plan>{};
    for (final group in plans['groups'] as List) {
      if (group is! Map ||
          (group['name'] ?? '').toString().toUpperCase().contains('SVIP'))
        continue;
      final entries = group['plans'];
      if (entries is! List) continue;
      for (final item in entries) {
        if (item is! Map || (item['status'] != null && item['status'] != 1))
          continue;
        final price = _integer(item['coinPrice']);
        final hours = _integer(item['durationHours']);
        final id = item['id'];
        if (price == null ||
            price <= 0 ||
            hours == null ||
            hours <= 0 ||
            id == null ||
            id.toString().isEmpty)
          continue;
        byDuration[hours] = _Plan(id, price, hours, item['name']);
      }
    }
    final eligible = byDuration.values
        .where((plan) => plan.price <= balance)
        .toList();
    if (eligible.isEmpty)
      return const CliCliMaintenanceResult('noAffordablePlan');
    final enough = eligible.where((p) => p.hours >= need).toList();
    final candidates = enough.isEmpty ? eligible : enough;
    candidates.sort((a, b) {
      final ratio = (a.price / a.hours * 1000000).round().compareTo(
        (b.price / b.hours * 1000000).round(),
      );
      return ratio != 0 ? ratio : a.price.compareTo(b.price);
    });
    final choice = candidates.first;
    final detail = <String, dynamic>{
      'planId': choice.id,
      'coins': choice.price,
      'hours': choice.hours,
      'name': choice.name,
      'remainingHours': remaining,
    };
    if (dryRun) return CliCliMaintenanceResult('dryRun', detail: detail);
    await store.write(
      CliCliMaintenanceRecord(
        signedDay: record.signedDay,
        watchProgressDay: record.watchProgressDay,
        taskCompleteDay: record.taskCompleteDay,
        renewedDay: record.renewedDay,
        pendingOrder: true,
      ),
    );
    Map<String, dynamic> response;
    try {
      response = await call('$_base/subscribe', <String, dynamic>{
        'planId': choice.id,
        'payMethod': 3,
      });
    } catch (_) {
      return CliCliMaintenanceResult('pendingOrder', detail: detail);
    }
    if (response['code'] == 200) {
      // A 200 from subscribe is not proof of a completed order: the endpoint
      // answers 200 for payment methods that perform no debit at all. Confirm by
      // re-reading the expiry and requiring it to move forward.
      final confirmed = await _confirmRenewal(expiry);
      if (!confirmed) {
        await store.write(
          CliCliMaintenanceRecord(
            signedDay: record.signedDay,
            watchProgressDay: record.watchProgressDay,
            taskCompleteDay: record.taskCompleteDay,
            renewedDay: record.renewedDay,
            pendingOrder: true,
          ),
        );
        return CliCliMaintenanceResult(
          'unconfirmedOrder',
          detail: {...detail, 'response': response},
        );
      }
      await store.write(
        CliCliMaintenanceRecord(
          signedDay: record.signedDay,
          watchProgressDay: record.watchProgressDay,
          taskCompleteDay: record.taskCompleteDay,
          renewedDay: day,
        ),
      );
      return CliCliMaintenanceResult(
        'renewed',
        detail: {...detail, 'response': response},
      );
    }
    // Do not guess undocumented error-code semantics for a debit request.
    if (isDefinitiveRejection?.call(response) == true) {
      await store.write(
        CliCliMaintenanceRecord(
          signedDay: record.signedDay,
        watchProgressDay: record.watchProgressDay,
        taskCompleteDay: record.taskCompleteDay,
          renewedDay: record.renewedDay,
        ),
      );
      return CliCliMaintenanceResult(
        'failed',
        detail: {...detail, 'response': response},
      );
    }
    return CliCliMaintenanceResult(
      'pendingOrder',
      detail: {...detail, 'response': response},
    );
  });

  /// Call only after independently checking the order/account. If confirmed
  /// successful, record the original order's local day to prevent duplicates.
  Future<void> resolvePendingOrder({
    required bool succeeded,
    required String orderDay,
  }) => store.synchronized(() async {
    final record = await store.read();
    if (!record.pendingOrder) throw StateError('No pending order to reconcile');
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(orderDay))
      throw ArgumentError.value(orderDay, 'orderDay');
    await store.write(
      CliCliMaintenanceRecord(
        signedDay: record.signedDay,
        watchProgressDay: record.watchProgressDay,
        taskCompleteDay: record.taskCompleteDay,
        renewedDay: succeeded ? orderDay : record.renewedDay,
      ),
    );
  });
}

Map<dynamic, dynamic>? _data(Map<String, dynamic> response) =>
    response['code'] == 200 && response['data'] is Map
    ? response['data'] as Map
    : null;

int? _integer(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}

class _Plan {
  const _Plan(this.id, this.price, this.hours, this.name);
  final dynamic id;
  final int price;
  final int hours;
  final dynamic name;
}
