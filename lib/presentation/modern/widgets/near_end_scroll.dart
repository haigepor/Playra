import 'package:flutter/widgets.dart';

/// 只响应主列表向下接近底部；横向海报、回看和布局变化不触发分页。
bool isNearEndScroll(ScrollNotification notification) =>
    notification.depth == 0 &&
    notification.metrics.axis == Axis.vertical &&
    notification.metrics.extentAfter < 240 &&
    (notification is ScrollUpdateNotification &&
            (notification.scrollDelta ?? 0) > 0 ||
        notification is OverscrollNotification && notification.overscroll > 0);
