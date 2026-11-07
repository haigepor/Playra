/// 仅调整页面名称；运行 ID、内容身份和用户历史保持原值。
String playbackSourceName(String id, String fallback, {bool anime = false}) =>
    switch (id) {
      'lumina' => '动漫 · Lumina',
      // 第二内容源在个人库与播放源行必须同名，否则记录里会露出接口 id。
      'whisklet' => 'Whisklet',
      'hongguo' => '红果短剧',
      'kazumi' => '已移除来源（记录保留）',
      'anifive' => '已移除来源（记录保留）',
      'miomedia' => '已移除来源（记录保留）',
      _ => fallback,
    };
