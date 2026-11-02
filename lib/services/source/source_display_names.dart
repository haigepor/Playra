/// 仅调整页面名称；运行 ID、内容身份和用户历史保持原值。
String playbackSourceName(String id, String fallback, {bool anime = false}) =>
    switch (id) {
      'lumina' => '动漫 · Lumina',
      'kazumi' => '动漫 · Kazumi',
      'anifive' => '已移除来源（记录保留）',
      'miomedia' => '已移除来源（记录保留）',
      _ => fallback,
    };
