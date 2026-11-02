import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/services/source/lumina/lumina_work_scheduler.dart';
import 'package:kazumi/services/source/source_models.dart';

void main() {
  testWidgets('preloads wait until foreground is finished and idle', (
    tester,
  ) async {
    final scheduler = LuminaWorkScheduler(
      idleDelay: const Duration(seconds: 1),
    );
    addTearDown(scheduler.dispose);
    final active = Completer<int>();
    var preloaded = false;
    final foreground = scheduler.run((_) => active.future, background: false);
    final background = scheduler.run((_) async {
      preloaded = true;
      return 2;
    }, background: true);
    await tester.pump(const Duration(seconds: 2));
    expect(preloaded, isFalse);
    active.complete(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 999));
    expect(preloaded, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(await foreground, 1);
    expect(await background, 2);
    scheduler.dispose();
  });

  testWidgets('foreground cancels background work without waiting for it', (
    tester,
  ) async {
    final scheduler = LuminaWorkScheduler(idleDelay: Duration.zero);
    addTearDown(scheduler.dispose);
    CancelToken? token;
    final release = Completer<void>();
    final background = scheduler.run((cancel) {
      token = cancel;
      return release.future;
    }, background: true);
    await tester.pump(const Duration(milliseconds: 1));
    expect(token, isNotNull);
    expect(await scheduler.run((_) async => 42, background: false), 42);
    expect(token!.isCancelled, isTrue);
    release.complete();
    await background;
    scheduler.dispose();
  });

  testWidgets('cancelled waiting preload never enters its action', (
    tester,
  ) async {
    final scheduler = LuminaWorkScheduler();
    addTearDown(scheduler.dispose);
    final cancel = CancelToken();
    var called = false;
    final result = scheduler.run(
      (_) async {
        called = true;
      },
      background: true,
      cancel: cancel,
    );
    final assertion = expectLater(result, throwsA(isA<SourceException>()));
    cancel.cancel();
    await tester.pump();
    await assertion;
    expect(called, isFalse);
    scheduler.dispose();
  });
}
