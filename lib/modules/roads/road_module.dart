class Road {
  /// 上游真实线路标识。旧规则未声明时为空，不用 UI 下标推导上游编号。
  String id;
  String name;
  List<String> data;
  List<String> identifier;

  Road({
    this.id = '',
    required this.name,
    required this.data,
    required this.identifier,
  });
}
