import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// 同一帧的多个来源通知只组装一次首页，保留最后的完整状态。
class HomeFrameUpdates extends ChangeNotifier {
  HomeFrameUpdates(this.sources) {
    for (final source in sources) {
      source.addListener(_queue);
    }
  }
  final List<Listenable> sources;
  int? _frame;
  void _queue() {
    _frame ??= SchedulerBinding.instance.scheduleFrameCallback((_) {
      _frame = null;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    for (final source in sources) {
      source.removeListener(_queue);
    }
    if (_frame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
    }
    super.dispose();
  }
}
