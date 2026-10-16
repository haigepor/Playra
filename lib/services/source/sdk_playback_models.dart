/// SDK 之间共用播放模型；来源 ID、线路代码与真实集数保持独立。
abstract class SdkVideo {
  const SdkVideo();
  String get id;
  String get title;
  String get categoryName;
  String get cover;
  String get poster;
  String get description;
  String get year;
  String get area;
  double get score;
  List<SdkLine> get lines;
  bool get singleMovie;
  bool get isAnime => false;
  String? get edition => null;
  String get subtitle => [
    year,
    area,
    categoryName,
  ].where((s) => s.isNotEmpty && s != '0').join(' · ');
}

class SdkVideoData extends SdkVideo {
  const SdkVideoData({
    required this.id,
    required this.title,
    this.categoryName = '',
    this.cover = '',
    this.poster = '',
    this.description = '',
    this.year = '',
    this.area = '',
    this.score = 0,
    this.lines = const [],
    this.singleMovie = false,
    this.edition,
  });
  @override
  final String id, title, categoryName, cover, poster, description, year, area;
  @override
  final double score;
  @override
  final List<SdkLine> lines;
  @override
  final bool singleMovie;
  @override
  final String? edition;
}

class SdkLine {
  const SdkLine(this.code, this.name);
  final String code, name;
  String get label => name.isEmpty ? code : name;
}

class SdkEpisode {
  const SdkEpisode({
    required this.number,
    required this.name,
    required this.code,
    this.vip = false,
    this.reference,
  });
  // 非数字的 SP/日期/上下篇没有真实集号，不能以目录下标替代来源身份。
  final int? number;
  final String name, code;
  final bool vip;
  final String? reference;
  String get identityKey => reference ?? '$number';
  String get label => name.isNotEmpty
      ? name
      : number == null
      ? '未命名剧集'
      : '第${number.toString().padLeft(2, '0')}集';
}

class SdkQuality {
  const SdkQuality(this.code, {this.name = '', this.height});
  final String code, name;
  // 空值表示证据不足；“原画/蓝光”这样的营销名称不虚构分辨率。
  final int? height;
  String get label => height == null ? '画质待确认' : '${height}p';
  String get choiceLabel => height == 2160 ? '4K' : label;

  static int? resolution(Object? value) {
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value >= 144 && value <= 16384 ? value.toInt() : null;
    }
    if (value is! String) return null;
    final text = value.trim().toLowerCase();
    final size = RegExp(r'^(\d{3,5})\s*[x×]\s*(\d{3,5})$').firstMatch(text);
    if (size != null) return resolution(int.tryParse(size[2]!));
    final p = RegExp(r'^(\d{3,5})p(?:\d{2,3})?$').firstMatch(text);
    if (p != null) return resolution(int.tryParse(p[1]!));
    return switch (text) {
      '4k' => 2160,
      '8k' => 4320,
      _ => null,
    };
  }

  static SdkQuality? fromJson(Map raw) {
    final code = raw['quality'];
    if (code is! String || code.isEmpty || code.length > 128) return null;
    final name = raw['label'] ?? raw['name'];
    return SdkQuality(
      code,
      name: name is String ? name : '',
      height:
          resolution(raw['height']) ??
          resolution(raw['resolution']) ??
          resolution(code) ??
          resolution(name),
    );
  }
}

class SdkLineCandidate {
  const SdkLineCandidate({
    required this.line,
    this.episode,
    this.qualities = const [],
    this.status = 'ready',
    this.qualityStatus = 'ready',
  });
  final SdkLine line;
  final SdkEpisode? episode;
  final List<SdkQuality> qualities;
  final String status;
  final String qualityStatus;
  SdkQuality? get bestQuality {
    SdkQuality? best;
    for (final quality in qualities) {
      if (best == null || (quality.height ?? 0) > (best.height ?? 0)) {
        best = quality;
      }
    }
    return best;
  }

  String get summary => switch (status) {
    'empty' => '暂无剧集',
    'mismatch' => '没有对应当前集',
    'timeout' => '查询超时，可手动重试',
    'failed' => '目录暂不可用，可重试',
    _ => bestQuality?.label ?? '画质待确认',
  };
}
