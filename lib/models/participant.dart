/// 参赛选手数据模型
/// 对应 CSV 文件中的数据结构
/// CSV 格式: 姓名,参赛编号,组别,头像名称,领队姓名
class Participant {
  final int id; // 内部ID（自动生成，基于行号）
  final String name; // 姓名
  final String memberCode; // 参赛编号
  final String? group; // 组别
  final String? avatarPath; // 头像名称（路径）
  final String? leaderName; // 领队姓名
  String? workCode; // 作品码（检录时绑定）
  int checkStatus; // 0=未检录, 1=已检录
  double? score; // 分数
  String? evidenceImg; // 评分照片路径

  Participant({
    required this.id,
    required this.name,
    required this.memberCode,
    this.group,
    this.avatarPath,
    this.leaderName,
    this.workCode,
    this.checkStatus = 0,
    this.score,
    this.evidenceImg,
  });

  /// 从 CSV 行数据创建 Participant
  /// CSV 格式: 姓名,参赛编号,组别,头像名称,领队姓名[,作品码,检录状态,分数,评分照片]
  /// 前5列为导入的基础数据，后4列为运行时数据（可选）
  factory Participant.fromCsvRow(List<dynamic> row, {required int rowIndex}) {
    return Participant(
      id: rowIndex, // 使用行号作为ID
      name: row[0].toString().trim(),
      memberCode: row[1].toString().trim(),
      group: row.length > 2 && row[2].toString().trim().isNotEmpty
          ? row[2].toString().trim()
          : null,
      avatarPath: row.length > 3 && row[3].toString().trim().isNotEmpty
          ? row[3].toString().trim()
          : null,
      leaderName: row.length > 4 && row[4].toString().trim().isNotEmpty
          ? row[4].toString().trim()
          : null,
      workCode: row.length > 5 && row[5].toString().trim().isNotEmpty
          ? row[5].toString().trim()
          : null,
      checkStatus: row.length > 6 ? (int.tryParse(row[6].toString()) ?? 0) : 0,
      score: row.length > 7 && row[7].toString().trim().isNotEmpty
          ? double.tryParse(row[7].toString())
          : null,
      evidenceImg: row.length > 8 && row[8].toString().trim().isNotEmpty
          ? row[8].toString().trim()
          : null,
    );
  }

  /// 转换为 CSV 行数据
  /// 输出格式: 姓名,参赛编号,组别,头像名称,领队姓名,作品码,检录状态,分数,评分照片
  List<dynamic> toCsvRow() {
    return [
      name,
      memberCode,
      group ?? '',
      avatarPath ?? '',
      leaderName ?? '',
      workCode ?? '',
      checkStatus,
      score?.toString() ?? '',
      evidenceImg ?? '',
    ];
  }

  /// 从 JSON 创建 Participant
  factory Participant.fromJson(Map<String, dynamic> json) {
    return Participant(
      id: json['id'] as int,
      name: json['name'] as String,
      memberCode: json['member_code'] as String,
      group: json['group'] as String?,
      avatarPath: json['avatar_path'] as String?,
      leaderName: json['leader_name'] as String?,
      workCode: json['work_code'] as String?,
      checkStatus: json['check_status'] as int? ?? 0,
      score: json['score'] as double?,
      evidenceImg: json['evidence_img'] as String?,
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'member_code': memberCode,
      'group': group,
      'avatar_path': avatarPath,
      'leader_name': leaderName,
      'work_code': workCode,
      'check_status': checkStatus,
      'score': score,
      'evidence_img': evidenceImg,
    };
  }

  /// 创建副本（用于不可变更新）
  /// 使用 Object 类型的哨兵值来区分"未传参数"和"传入null"
  static const _sentinel = Object();

  Participant copyWith({
    int? id,
    String? name,
    String? memberCode,
    Object? group = _sentinel,
    Object? avatarPath = _sentinel,
    Object? leaderName = _sentinel,
    Object? workCode = _sentinel,
    int? checkStatus,
    Object? score = _sentinel,
    Object? evidenceImg = _sentinel,
  }) {
    return Participant(
      id: id ?? this.id,
      name: name ?? this.name,
      memberCode: memberCode ?? this.memberCode,
      group: group == _sentinel ? this.group : group as String?,
      avatarPath: avatarPath == _sentinel
          ? this.avatarPath
          : avatarPath as String?,
      leaderName: leaderName == _sentinel
          ? this.leaderName
          : leaderName as String?,
      workCode: workCode == _sentinel ? this.workCode : workCode as String?,
      checkStatus: checkStatus ?? this.checkStatus,
      score: score == _sentinel ? this.score : score as double?,
      evidenceImg: evidenceImg == _sentinel
          ? this.evidenceImg
          : evidenceImg as String?,
    );
  }

  @override
  String toString() {
    return 'Participant(id: $id, name: $name, memberCode: $memberCode, '
        'group: $group, leaderName: $leaderName, '
        'workCode: $workCode, checkStatus: $checkStatus, score: $score)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Participant &&
        other.id == id &&
        other.memberCode == memberCode;
  }

  @override
  int get hashCode => id.hashCode ^ memberCode.hashCode;
}
