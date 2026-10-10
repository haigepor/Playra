import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kazumi/presentation/interface_style.dart';

void main() {
  test('defaults and unknown stored styles keep the legacy interface', () {
    for (final value in ['legacy', '', 'future-style']) {
      final controller = InterfaceStyleController(
        supportsModern: true,
        savedStyle: value,
        writeStyle: (_) async {},
      );
      expect(controller.style, InterfaceStyle.legacy);
      controller.dispose();
    }
  });

  test('switches both ways and restores the persisted selection', () async {
    var saved = 'legacy';
    final controller = InterfaceStyleController(
      supportsModern: true,
      savedStyle: saved,
      writeStyle: (value) async => saved = value,
    );
    expect(await controller.setStyle(InterfaceStyle.modern), isTrue);
    expect(saved, 'modern');
    expect(controller.style, InterfaceStyle.modern);
    final restarted = InterfaceStyleController(
      supportsModern: true,
      savedStyle: saved,
      writeStyle: (_) async {},
    );
    expect(restarted.style, InterfaceStyle.modern);
    expect(await controller.setStyle(InterfaceStyle.legacy), isTrue);
    expect(saved, 'legacy');
    controller.dispose();
    restarted.dispose();
  });

  test(
    'unsupported platforms use legacy without changing the stored preference',
    () async {
      var writes = 0;
      final controller = InterfaceStyleController(
        supportsModern: false,
        savedStyle: 'modern',
        writeStyle: (_) async {
          writes++;
        },
      );
      expect(controller.style, InterfaceStyle.legacy);
      expect(await controller.setStyle(InterfaceStyle.modern), isFalse);
      expect(writes, 0);
      controller.dispose();
    },
  );

  test('a failed save does not change the visible interface', () async {
    final controller = InterfaceStyleController(
      supportsModern: true,
      savedStyle: 'legacy',
      writeStyle: (_) async => throw StateError('disk full'),
    );
    await expectLater(
      controller.setStyle(InterfaceStyle.modern),
      throwsStateError,
    );
    expect(controller.style, InterfaceStyle.legacy);
    expect(controller.isSaving, isFalse);
    controller.dispose();
  });

  test('a pending save prevents competing style writes', () async {
    final save = Completer<void>();
    final controller = InterfaceStyleController(
      supportsModern: true,
      savedStyle: 'legacy',
      writeStyle: (_) => save.future,
    );
    final change = controller.setStyle(InterfaceStyle.modern);
    expect(controller.isSaving, isTrue);
    expect(controller.style, InterfaceStyle.legacy);
    expect(await controller.setStyle(InterfaceStyle.modern), isFalse);
    save.complete();
    await change;
    expect(controller.style, InterfaceStyle.modern);
    controller.dispose();
  });

  test(
    'restored settings update the interface and stop listening after disposal',
    () async {
      final changes = StreamController<String>();
      final controller = InterfaceStyleController(
        supportsModern: true,
        savedStyle: 'legacy',
        writeStyle: (_) async {},
        savedStyleChanges: changes.stream,
      );
      changes.add('modern');
      await Future<void>.delayed(Duration.zero);
      expect(controller.style, InterfaceStyle.modern);
      controller.dispose();
      expect(changes.hasListener, isFalse);
      await changes.close();
    },
  );
}
