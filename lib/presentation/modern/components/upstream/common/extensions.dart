import 'package:flutter/widgets.dart';

extension GalleryListSpacing on Iterable<Widget> {
  List<Widget> separatedBy(Widget separator) {
    final result = <Widget>[];
    for (final widget in this) {
      if (result.isNotEmpty) result.add(separator);
      result.add(widget);
    }
    return result;
  }
}

extension GalleryCapitalization on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
