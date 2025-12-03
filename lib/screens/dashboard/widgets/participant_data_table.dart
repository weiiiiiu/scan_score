import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/participant.dart';
import '../../../providers/participant_provider.dart';

/// 参赛者数据表格组件
/// 展示所有参赛者的详细信息，使用卡片列表形式
class ParticipantDataTable extends StatefulWidget {
  /// 搜索过滤文本
  final String? searchQuery;

  /// 点击行时的回调
  final void Function(Participant)? onRowTap;

  const ParticipantDataTable({super.key, this.searchQuery, this.onRowTap});

  @override
  State<ParticipantDataTable> createState() => _ParticipantDataTableState();
}

class _ParticipantDataTableState extends State<ParticipantDataTable> {
  bool _sortAscending = true;
  // 筛选状态：null=全部, 1=已检录, 0=未检录
  int? _filterCheckStatus;

  // 预定义颜色，避免每次 build 重新创建
  static final _blueLight = Colors.blue.shade50;
  static final _blueDark = Colors.blue.shade700;
  static final _greyLight = Colors.grey.shade300;
  static final _greyDark = Colors.grey.shade600;
  static final _greyText = Colors.grey.shade700;

  @override
  Widget build(BuildContext context) {
    return Consumer<ParticipantProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!provider.hasData) {
          return const Center(child: Text('暂无数据，请先导入 CSV 名单'));
        }

        // 过滤数据
        List<Participant> data = widget.searchQuery?.isNotEmpty == true
            ? provider.search(widget.searchQuery!)
            : provider.participants;

        // 根据检录状态筛选
        if (_filterCheckStatus != null) {
          data = data
              .where((p) => p.checkStatus == _filterCheckStatus)
              .toList();
        }

        // 按证号排序
        data = _sortData(data);

        return Column(
          children: [
            // 标题栏和排序选项
            _buildHeader(data.length),
            // 列表
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: data.length,
                cacheExtent: 500, // 增加缓存区域
                itemBuilder: (context, index) {
                  return _ParticipantCard(
                    key: ValueKey(data[index].id),
                    participant: data[index],
                    onTap: widget.onRowTap,
                    blueLight: _blueLight,
                    blueDark: _blueDark,
                    greyLight: _greyLight,
                    greyDark: _greyDark,
                    greyText: _greyText,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(int count) {
    return Consumer<ParticipantProvider>(
      builder: (context, provider, child) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：标题和排序
              Row(
                children: [
                  Text('参赛者名单', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  // 按证号排序
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _sortAscending = !_sortAscending),
                    icon: Icon(
                      _sortAscending
                          ? Icons.arrow_upward
                          : Icons.arrow_downward,
                      size: 16,
                    ),
                    label: Text(
                      '证号${_sortAscending ? "↑" : "↓"}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 第二行：统计信息（可点击筛选）
              Row(
                children: [
                  _FilterBadge(
                    label: '总',
                    value: provider.totalCount,
                    color: Colors.blue,
                    isSelected: _filterCheckStatus == null,
                    onTap: () => setState(() => _filterCheckStatus = null),
                  ),
                  const SizedBox(width: 8),
                  _FilterBadge(
                    label: '已检录',
                    value: provider.checkedInCount,
                    color: Colors.green,
                    isSelected: _filterCheckStatus == 1,
                    onTap: () => setState(() {
                      _filterCheckStatus = _filterCheckStatus == 1 ? null : 1;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _FilterBadge(
                    label: '未检录',
                    value: provider.uncheckedCount,
                    color: Colors.orange,
                    isSelected: _filterCheckStatus == 0,
                    onTap: () => setState(() {
                      _filterCheckStatus = _filterCheckStatus == 0 ? null : 0;
                    }),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  List<Participant> _sortData(List<Participant> data) {
    final sorted = List<Participant>.from(data);
    sorted.sort((a, b) {
      final result = a.memberCode.compareTo(b.memberCode);
      return _sortAscending ? result : -result;
    });
    return sorted;
  }
}

/// 可点击的筛选标签组件
class _FilterBadge extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterBadge({
    required this.label,
    required this.value,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? null
              : Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Text(
          '$label $value',
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 独立的卡片组件，避免不必要的重建
class _ParticipantCard extends StatelessWidget {
  final Participant participant;
  final void Function(Participant)? onTap;
  final Color blueLight;
  final Color blueDark;
  final Color greyLight;
  final Color greyDark;
  final Color greyText;

  const _ParticipantCard({
    super.key,
    required this.participant,
    this.onTap,
    required this.blueLight,
    required this.blueDark,
    required this.greyLight,
    required this.greyDark,
    required this.greyText,
  });

  @override
  Widget build(BuildContext context) {
    final isCheckedIn = participant.checkStatus == 1;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: onTap != null ? () => onTap!(participant) : null,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：参赛证号、姓名、检录状态
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 参赛证号
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: blueLight,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      participant.memberCode,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: blueDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 姓名
                  Expanded(
                    child: Text(
                      participant.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 检录状态
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isCheckedIn ? Colors.green : greyLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isCheckedIn ? '已检录' : '未检录',
                      style: TextStyle(
                        fontSize: 11,
                        color: isCheckedIn ? Colors.white : greyText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 第二行：组别、项目、队名、辅导员
              Row(
                children: [
                  _InfoChip(
                    label: '组别',
                    value: participant.group,
                    greyDark: greyDark,
                  ),
                  _InfoChip(
                    label: '项目',
                    value: participant.project,
                    greyDark: greyDark,
                  ),
                  _InfoChip(
                    label: '队名',
                    value: participant.teamName,
                    greyDark: greyDark,
                  ),
                  _InfoChip(
                    label: '辅导员',
                    value: participant.instructorName,
                    greyDark: greyDark,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 信息标签组件
class _InfoChip extends StatelessWidget {
  final String label;
  final String? value;
  final Color greyDark;

  const _InfoChip({
    required this.label,
    required this.value,
    required this.greyDark,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: greyDark)),
            Text(
              value ?? '-',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
