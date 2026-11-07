import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/pages/menu/route_visibility.dart';
import 'package:kazumi/presentation/modern/modern_shell.dart';
import 'package:kazumi/presentation/modern/widgets/native_liquid_navigation.dart';
import 'package:kazumi/utils/constants.dart';

void main() {
  testWidgets(
    'official native navigation synchronizes tabs, bounds and visibility',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      tester.view.physicalSize = const Size(1280, 853);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final calls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        NativeLiquidNavigationController.channel,
        (call) async {
          calls.add(call);
          return call.method == 'initialize' ? true : null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          NativeLiquidNavigationController.channel,
          null,
        ),
      );
      var selected = 0;
      var covered = false;
      late StateSetter update;
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          theme: ThemeData(pageTransitionsTheme: pageTransitionsTheme2024),
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return RouteVisibility(
                isCovered: covered,
                child: ModernShell(
                  selectedIndex: selected,
                  selectDestination: (index) =>
                      setState(() => selected = index),
                  outlet: const Center(child: Text('page content')),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NativeLiquidNavigationBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      Map<Object?, Object?> lastUpdate() =>
          calls.lastWhere((call) => call.method == 'update').arguments as Map;
      expect(lastUpdate()['width'], 440);
      expect(lastUpdate()['left'], 420);
      expect(lastUpdate()['visible'], isTrue);
      final reply = Completer<void>();
      tester.binding.channelBuffers.push(
        NativeLiquidNavigationController.channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('selectTab', 2),
        ),
        (_) => reply.complete(),
      );
      await reply.future;
      await tester.pumpAndSettle();
      expect(selected, 2);
      expect(lastUpdate()['selectedIndex'], 2);
      update(() => covered = true);
      await tester.pumpAndSettle();
      expect(lastUpdate()['visible'], isFalse);
      update(() => covered = false);
      await tester.pumpAndSettle();
      expect(lastUpdate()['visible'], isTrue);
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('detail page')),
          ),
        ),
      );
      update(() => covered = true);
      await tester.pumpAndSettle();
      expect(lastUpdate()['visible'], isFalse);
      navigator.currentState!.pop();
      update(() => covered = false);
      await tester.pump();
      expect(lastUpdate()['visible'], isFalse);
      await tester.pumpAndSettle();
      expect(lastUpdate()['visible'], isTrue);
      expect(lastUpdate()['left'], 420);
      expect(lastUpdate()['width'], 440);
      unawaited(
        showDialog<void>(
          context: navigator.currentContext!,
          builder: (_) => const AlertDialog(content: Text('dialog content')),
        ),
      );
      await tester.pumpAndSettle();
      expect(lastUpdate()['visible'], isFalse);
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(lastUpdate()['visible'], isTrue);
      tester.view.physicalSize = const Size(390, 844);
      await tester.pumpAndSettle();
      expect(lastUpdate()['width'], 358);
      expect(lastUpdate()['left'], 16);
      expect(selected, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'dispose'), hasLength(1));
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );
}
