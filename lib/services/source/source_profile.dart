/// 来源技术类型与内容领域分开，缺失声明不默认归为动漫。
class SourceProfile {
  const SourceProfile({required this.domains, this.adapterKind = 'rule'});
  final List<String> domains;
  final String adapterKind;

  factory SourceProfile.fromJson(Map<String, dynamic> rule) {
    final options = rule['sourceConfig'] as Map? ?? const {};
    final declared = options['domains'];
    final type = rule['type'];
    final domains = declared is List
        ? declared
              .whereType<String>()
              .where(const ['anime', 'screen'].contains)
              .toSet()
              .toList()
        : type == 'anime'
        ? <String>['anime']
        : const [
            'movie',
            'tv',
            'variety',
            'comic',
            'documentary',
          ].contains(type)
        ? <String>['screen']
        : <String>[];
    return SourceProfile(
      domains: domains,
      adapterKind: options['resolveApi'] is Map ? 'http' : 'rule',
    );
  }

  String get label => domains.isEmpty
      ? '未分类'
      : domains.map((d) => d == 'anime' ? '动漫' : '影视').join(' / ');
  bool supports(String domain) => domains.contains(domain);
  Map<String, dynamic> toJson() => {
    'domains': domains,
    'adapterKind': adapterKind,
  };
}
