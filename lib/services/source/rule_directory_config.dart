// 专用站点的目录配置集中在来源层；自定义规则可以通过 sourceConfig.catalog 扩展。
Map<String, dynamic>? directoryConfig(Map<String, dynamic> rule) {
  final config = (rule['sourceConfig'] as Map?)?['catalog'];
  if (config is Map &&
      config['entrySelector'] is String &&
      config['detailPathPattern'] is String) {
    return Map<String, dynamic>.from(config);
  }
  if (const [
    'dm84',
    '7sefun',
  ].contains(rule['name']?.toString().toLowerCase())) {
    return const {
      'entrySelector': 'a.title[href], a.video-wrapper[href]',
      'detailPathPattern': r'/(?:v|voddetail)/',
      'priority': 10,
    };
  }
  return null;
}

int directoryPriority(Map<String, dynamic> rule) {
  final configured = directoryConfig(rule)?['priority'];
  if (rule['name']?.toString().toLowerCase() == 'dm84') return 0;
  return configured is int ? configured : 100;
}
