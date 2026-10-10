import 'package:flutter/foundation.dart';

enum ImageAcceleration {
  direct,
  ech,
  mirror;

  static ImageAcceleration fromSetting(String value) =>
      kIsWeb && (value == 'ech' || value.isEmpty)
      ? direct
      : values.firstWhere(
          (mode) => mode.name == value,
          orElse: () => kIsWeb ? direct : ech,
        );
}
