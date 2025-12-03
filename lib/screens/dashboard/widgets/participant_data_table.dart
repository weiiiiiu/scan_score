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
                itemBuilder: (context, index) {
                  return _buildParticipantCard(data[index], index);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeader(int count) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Text('参赛者名单', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '共 $count 人',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Spacer(),
          // 按证号排序
          TextButton.icon(
            onPressed: () => setState(() => _sortAscending = !_sortAscending),
            icon: Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
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
    );
  }

  Widget _buildParticipantCard(Participant p, int index) {
    final isCheckedIn = p.checkStatus == 1;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: widget.onRowTap != null ? () => widget.onRowTap!(p) : null,
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
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      p.memberCode,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 姓名 - 允许换行显示完整
                  Expanded(
                    child: Text(
                      p.name,
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
                      color: isCheckedIn ? Colors.green : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      isCheckedIn ? '已检录' : '未检录',
                      style: TextStyle(
                        fontSize: 11,
                        color: isCheckedIn
                            ? Colors.white
                            : Colors.grey.shade700,
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
                  _buildInfoChip('组别', p.group),
                  _buildInfoChip('项目', p.project),
                  _buildInfoChip('队名', p.teamName),
                  _buildInfoChip('辅导员', p.instructorName),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, String? value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
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

  List<Participant> _sortData(List<Participant> data) {
    final sorted = List<Participant>.from(data);
    sorted.sort((a, b) {
      final result = a.memberCode.compareTo(b.memberCode);
      return _sortAscending ? result : -result;
    });
    return sorted;
  }
}
