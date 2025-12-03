/// 参赛选手数据模型
/// 对应 CSV 文件中的数据结构
/// CSV 格式: 参赛证号,姓名,组别,项目,队名,辅导员
class Participant {
  final int id; // 内部ID（自动生成，基于行号）
  final String name; // 姓名
  final String memberCode; // 参赛证号
  final String? group; // 组别
  final String? project; // 项目
  final String? teamName; // 队名
  final String? instructorName; // 辅导员
  String? workCode; // 作品码（检录时绑定）
  int checkStatus; // 0=未检录, 1=已检录
  double? score; // 分数
  String? evidenceImg; // 评分照片路径

  Participant({
    required this.id,
    required this.name,
    required this.memberCode,
    this.group,
    this.project,
    this.teamName,
    this.instructorName,
    this.workCode,
    this.checkStatus = 0,
    this.score,
    this.evidenceImg,
  });

  /// 从 CSV 行数据创建 Participant
  /// CSV 格式: 参赛证号,姓名,组别,项目,队名,辅导员[,作品码,检录状态,分数,评分照片]
  /// 前6列为导入的基础数据，后4列为运行时数据
  factory Participant.fromCsvRow(List<dynamic> row, {required int rowIndex}) {
    return Participant(
      id: rowIndex, // 使用行号作为ID
      memberCode: row[0].toString().trim(),
      name: row[1].toString().trim(),
      group: row.length > 2 && row[2].toString().trim().isNotEmpty
          ? row[2].toString().trim()
          : null,
      project: row.length > 3 && row[3].toString().trim().isNotEmpty
          ? row[3].toString().trim()
          : null,
      teamName: row.length > 4 && row[4].toString().trim().isNotEmpty
          ? row[4].toString().trim()
          : null,
      instructorName: row.length > 5 && row[5].toString().trim().isNotEmpty
          ? row[5].toString().trim()
          : null,
      workCode: row.length > 6 && row[6].toString().trim().isNotEmpty
          ? row[6].toString().trim()
          : null,
      checkStatus: row.length > 7 ? (int.tryParse(row[7].toString()) ?? 0) : 0,
      score: row.length > 8 && row[8].toString().trim().isNotEmpty
          ? double.tryParse(row[8].toString())
          : null,
      evidenceImg: row.length > 9 && row[9].toString().trim().isNotEmpty
          ? row[9].toString().trim()
          : null,
    );
  }

  /// 转换为 CSV 行数据
  /// 输出格式: 参赛证号,姓名,组别,项目,队名,辅导员,作品码,检录状态,分数,评分照片
  List<dynamic> toCsvRow() {
    return [
      memberCode,
      name,
      group ?? '',
      project ?? '',
      teamName ?? '',
      instructorName ?? '',
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
      project: json['project'] as String?,
      teamName: json['team_name'] as String?,
      instructorName: json['instructor_name'] as String?,
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
      'project': project,
      'team_name': teamName,
      'instructor_name': instructorName,
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
    Object? project = _sentinel,
    Object? teamName = _sentinel,
    Object? instructorName = _sentinel,
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
      project: project == _sentinel ? this.project : project as String?,
      teamName: teamName == _sentinel ? this.teamName : teamName as String?,
      instructorName: instructorName == _sentinel
          ? this.instructorName
          : instructorName as String?,
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
        'group: $group, project: $project, teamName: $teamName, '
        'instructorName: $instructorName, workCode: $workCode, '
        'checkStatus: $checkStatus, score: $score)';
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
