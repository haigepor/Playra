import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/platform/browser_file_system.dart' as browser;

void main() {
  late io.Directory temporary;
  setUp(() async {
    temporary = await io.Directory.systemTemp.createTemp('kazumi-browser-fs-');
    Hive.init(temporary.path);
    await browser.initializeBrowserFiles();
  });
  tearDown(() async {
    await Hive.close();
    await temporary.delete(recursive: true);
  });
  test('rule JSON remains readable after storage is reopened', () async {
    await browser.Directory('/kazumi/plugins').create(recursive: true);
    await browser.File('/kazumi/plugins/rules.json').writeAsString('规则测试');
    await Hive.close();
    await browser.initializeBrowserFiles();
    expect(
      await browser.File('/kazumi/plugins/rules.json').readAsString(),
      '规则测试',
    );
  });
  test('download chunks append and survive rename', () async {
    final file = browser.File('/kazumi/download.tmp');
    await file.writeAsBytes([1, 2]);
    final handle = await file.open(mode: io.FileMode.append);
    await handle.writeFrom([3, 4]);
    await handle.close();
    final renamed = await file.rename('/kazumi/download.mp4');
    expect(await renamed.readAsBytes(), [1, 2, 3, 4]);
    expect(await file.exists(), false);
  });
  test('recursive listing and deletion respect directory boundaries', () async {
    await browser.File('/a/sub/item').writeAsBytes([1]);
    await browser.File('/ab/keep').writeAsBytes([2]);
    expect(await browser.Directory('/a').list(recursive: true).length, 2);
    await browser.Directory('/a').delete(recursive: true);
    expect(await browser.File('/a/sub/item').exists(), false);
    expect(await browser.File('/ab/keep').exists(), true);
  });
  test(
    'missing file fails rather than returning an empty successful read',
    () async {
      expect(
        browser.File('/missing').readAsBytes(),
        throwsA(isA<io.FileSystemException>()),
      );
    },
  );
}
