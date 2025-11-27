import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/participant.dart';
import '../../../providers/participant_provider.dart';

/// 参赛者数据表格组件
/// 展示所有参赛者的详细信息，支持排序和分页
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
  int _sortColumnIndex = 0;
  bool _sortAscending = true;
  int _rowsPerPage = 10;

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

        // 排序
        data = _sortData(data);

        return SingleChildScrollView(
          child: PaginatedDataTable(
            header: Row(
              children: [
                Text('参赛者名单', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(width: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '共 ${data.length} 人',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            rowsPerPage: _rowsPerPage,
            availableRowsPerPage: const [5, 10, 20, 50],
            onRowsPerPageChanged: (value) {
              if (value != null) {
                setState(() {
                  _rowsPerPage = value;
                });
              }
            },
            sortColumnIndex: _sortColumnIndex,
            sortAscending: _sortAscending,
            columns: [
              DataColumn(
                label: const Text('姓名'),
                onSort: (index, ascending) => _onSort(index, ascending),
              ),
              DataColumn(
                label: const Text('参赛编号'),
                onSort: (index, ascending) => _onSort(index, ascending),
              ),
              DataColumn(
                label: const Text('组别'),
                onSort: (index, ascending) => _onSort(index, ascending),
              ),
              DataColumn(
                label: const Text('领队'),
                onSort: (index, ascending) => _onSort(index, ascending),
              ),
              DataColumn(
                label: const Text('检录状态'),
                onSort: (index, ascending) => _onSort(index, ascending),
              ),
              DataColumn(
                label: const Text('作品码'),
                onSort: (index, ascending) => _onSort(index, ascending),
              ),
              DataColumn(
                label: const Text('分数'),
                numeric: true,
                onSort: (index, ascending) => _onSort(index, ascending),
              ),
            ],
            source: _ParticipantDataSource(
              data: data,
              onRowTap: widget.onRowTap,
              context: context,
            ),
          ),
        );
      },
    );
  }

  void _onSort(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
    });
  }

  List<Participant> _sortData(List<Participant> data) {
    final sorted = List<Participant>.from(data);

    sorted.sort((a, b) {
      int result;
      switch (_sortColumnIndex) {
        case 0: // 姓名
          result = a.name.compareTo(b.name);
          break;
        case 1: // 参赛编号
          result = a.memberCode.compareTo(b.memberCode);
          break;
        case 2: // 组别
          result = (a.group ?? '').compareTo(b.group ?? '');
          break;
        case 3: // 领队
          result = (a.leaderName ?? '').compareTo(b.leaderName ?? '');
          break;
        case 4: // 检录状态
          result = a.checkStatus.compareTo(b.checkStatus);
          break;
        case 5: // 作品码
          result = (a.workCode ?? '').compareTo(b.workCode ?? '');
          break;
        case 6: // 分数
          result = (a.score ?? 0).compareTo(b.score ?? 0);
          break;
        default:
          result = 0;
      }
      return _sortAscending ? result : -result;
    });

    return sorted;
  }
}

/// 数据源
class _ParticipantDataSource extends DataTableSource {
  final List<Participant> data;
  final void Function(Participant)? onRowTap;
  final BuildContext context;

  _ParticipantDataSource({
    required this.data,
    required this.onRowTap,
    required this.context,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= data.length) return null;

    final participant = data[index];

    return DataRow.byIndex(
      index: index,
      onSelectChanged: onRowTap != null ? (_) => onRowTap!(participant) : null,
      cells: [
        DataCell(Text(participant.name)),
        DataCell(Text(participant.memberCode)),
        DataCell(Text(participant.group ?? '-')),
        DataCell(Text(participant.leaderName ?? '-')),
        DataCell(_buildStatusChip(participant.checkStatus)),
        DataCell(Text(participant.workCode ?? '-')),
        DataCell(
          participant.score != null
              ? Text(
                  participant.score!.toStringAsFixed(1),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                )
              : const Text('-'),
        ),
      ],
    );
  }

  Widget _buildStatusChip(int status) {
    final isCheckedIn = status == 1;
    return Chip(
      label: Text(
        isCheckedIn ? '已检录' : '未检录',
        style: TextStyle(
          fontSize: 12,
          color: isCheckedIn ? Colors.white : Colors.grey[700],
        ),
      ),
      backgroundColor: isCheckedIn ? Colors.green : Colors.grey[300],
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => data.length;

  @override
  int get selectedRowCount => 0;
}
