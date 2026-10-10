import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kazumi/services/storage/hive_box_archive.dart';

void main() {
  test('IndexedDB box export uses native Hive backup framing', () async {
    final directory = await Directory.systemTemp.createTemp('kazumi-archive-');
    Hive.init(directory.path);
    try {
      final source = await Hive.openBox<dynamic>('archive-source');
      await source.putAll({
        '中文键': {'title': '收藏', 'progress': 12},
        42: [true, 9],
      });
      final archive = encodeHiveBox(source);
      final imported = await Hive.openBox<dynamic>(
        'archive-imported',
        bytes: archive,
      );
      expect(imported.toMap(), source.toMap());
      final file = File('${directory.path}/native.hive');
      await file.writeAsBytes(archive);
      await imported.close();
      final native = await Hive.openBox<dynamic>('native');
      expect(native.toMap(), source.toMap());
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
