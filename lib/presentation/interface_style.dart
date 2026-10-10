import 'dart:async';
import 'package:flutter/foundation.dart';

enum InterfaceStyle {
  legacy('旧版界面'),
  modern('新版界面（预览）');

  const InterfaceStyle(this.label);
  final String label;

  static InterfaceStyle fromValue(String value) =>
      value == 'modern' ? modern : legacy;
}

/// 只保存页面版本；收藏、历史、规则和下载仍由原有根模块管理。
class InterfaceStyleController extends ChangeNotifier {
  InterfaceStyleController({
    required this.supportsModern,
    required String savedStyle,
    required Future<void> Function(String) writeStyle,
    Stream<String>? savedStyleChanges,
  }) : _savedStyle = InterfaceStyle.fromValue(savedStyle),
       _writeStyle = writeStyle {
    _subscription = savedStyleChanges?.listen((value) {
      // Hive 可能在写入 Future 完成前发出事件，失败时不能提前切换界面。
      if (_isSaving || _disposed) return;
      final next = InterfaceStyle.fromValue(value);
      if (next == _savedStyle) return;
      _savedStyle = next;
      notifyListeners();
    });
  }

  final bool supportsModern;
  final Future<void> Function(String) _writeStyle;
  StreamSubscription<String>? _subscription;
  InterfaceStyle _savedStyle;
  bool _isSaving = false;
  bool _disposed = false;

  InterfaceStyle get style =>
      supportsModern ? _savedStyle : InterfaceStyle.legacy;
  bool get isSaving => _isSaving;

  Future<bool> setStyle(InterfaceStyle next) async {
    if (!supportsModern || _isSaving || _disposed || next == style) {
      return false;
    }
    _isSaving = true;
    notifyListeners();
    try {
      await _writeStyle(next.name);
      if (_disposed) return false;
      _savedStyle = next;
      return true;
    } finally {
      _isSaving = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
