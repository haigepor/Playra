/// 仅调整页面名称；运行 ID、内容身份和用户历史保持原值。
String playbackSourceName(String id, String fallback, {bool anime = false}) =>
    switch (id) {
      'lumina' => '动漫 · Lumina',
      'anifive' => '动漫 · AniFive',
      'miomedia' => anime ? '动漫备用 · MioMedia' : '影视 · MioMedia',
      _ => fallback,
    };
