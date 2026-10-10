// ignore_for_file: implementation_imports
import 'dart:typed_data';
import 'package:hive_ce/hive.dart';
import 'package:hive_ce/src/binary/binary_writer_impl.dart';
import 'package:hive_ce/src/binary/frame.dart';

/// IndexedDB 没有 .hive 文件；使用相同版本的帧编码保持与原生备份互通。
/// Hive CE 升级时必须运行跨平台备份兼容性测试。
Uint8List encodeHiveBox(Box<dynamic> box) {
  final writer = BinaryWriterImpl(Hive);
  for (final entry in box.toMap().entries) {
    writer.writeFrame(Frame(entry.key as Object, entry.value));
  }
  return writer.toBytes();
}
