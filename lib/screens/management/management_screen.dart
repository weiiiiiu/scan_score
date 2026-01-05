import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/participant_provider.dart';
import '../../models/participant.dart';
import '../../services/storage_service.dart';
import '../../services/file_service.dart';
import '../../services/activation_service.dart';
import '../../config/routes.dart';

/// 管理界面
class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  final StorageService _storageService = StorageService();
  final FileService _fileService = FileService();
  final ActivationService _activationService = ActivationService();

  String _searchQuery = '';
  String _filterGroup = '全部';
  String _filterStatus = '全部';

  List<String> get _groups {
    final provider = context.read<ParticipantProvider>();
    final groups = provider.participants
        .map((p) => p.group ?? '未分组')
        .toSet()
        .toList();
    groups.sort();
    return ['全部', ...groups];
  }

  List<Participant> get _filteredParticipants {
    final provider = context.watch<ParticipantProvider>();
    var list = provider.participants;

    // 搜索过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list
          .where(
            (p) =>
                p.name.toLowerCase().contains(query) ||
                p.memberCode.toLowerCase().contains(query),
          )
          .toList();
    }

    // 组别过滤
    if (_filterGroup != '全部') {
      list = list.where((p) => (p.group ?? '未分组') == _filterGroup).toList();
    }

    // 状态过滤
    if (_filterStatus == '已检录') {
      list = list.where((p) => p.checkStatus == 1).toList();
    } else if (_filterStatus == '未检录') {
      list = list.where((p) => p.checkStatus == 0).toList();
    } else if (_filterStatus == '已评分') {
      list = list.where((p) => p.score != null).toList();
    } else if (_filterStatus == '未评分') {
      list = list.where((p) => p.score == null).toList();
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('数据管理'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<ParticipantProvider>().refresh();
            },
            tooltip: '刷新数据',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'clear_all_checkin',
                child: Text('清除所有检录状态'),
              ),
              const PopupMenuItem(
                value: 'clear_all_scores',
                child: Text('清除所有评分'),
              ),
              const PopupMenuItem(
                value: 'clear_all_data',
                child: Text('清除所有数据'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'deactivate',
                child: Text('解绑激活', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索和过滤栏
          _buildSearchAndFilterBar(),
          // 数据列表
          Expanded(child: _buildParticipantList()),
        ],
      ),
    );
  }

  Widget _buildSearchAndFilterBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade100,
      child: Column(
        children: [
          // 搜索框
          TextField(
            decoration: InputDecoration(
              hintText: '搜索姓名/证号/项目/队名/辅导员/组别',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
          ),
          const SizedBox(height: 12),
          // 过滤选项
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filterGroup,
                  decoration: const InputDecoration(
                    labelText: '组别',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                  ),
                  items: _groups
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _filterGroup = value ?? '全部';
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _filterStatus,
                  decoration: const InputDecoration(
                    labelText: '状态',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                    isDense: true,
                  ),
                  items: ['全部', '已检录', '未检录', '已评分', '未评分']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _filterStatus = value ?? '全部';
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildParticipantList() {
    final participants = _filteredParticipants;

    if (participants.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '没有找到匹配的选手',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: participants.length,
      itemBuilder: (context, index) {
        final participant = participants[index];
        return _buildParticipantCard(participant);
      },
    );
  }

  Widget _buildParticipantCard(Participant participant) {
    final isCheckedIn = participant.checkStatus == 1;
    final hasScore = participant.score != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCheckedIn ? Colors.green : Colors.grey,
          child: Text(
            participant.name.isNotEmpty ? participant.name[0] : '?',
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(
          participant.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '编号: ${participant.memberCode} | 组别: ${participant.group ?? "未分组"}',
            ),
            Row(
              children: [
                _buildStatusChip(
                  isCheckedIn ? '已检录' : '未检录',
                  isCheckedIn ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                if (participant.workCode != null &&
                    participant.workCode!.isNotEmpty)
                  _buildStatusChip('作品码: ${participant.workCode}', Colors.blue),
                if (hasScore)
                  _buildStatusChip('名次: ${participant.score}', Colors.purple),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            AppRoutes.navigateToParticipantDetail(context, participant);
          },
        ),
        isThreeLine: true,
        onTap: () {
          AppRoutes.navigateToParticipantDetail(context, participant);
        },
      ),
    );
  }

  Widget _buildStatusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'clear_all_checkin':
        _showConfirmDialog(
          '确定清除所有检录状态吗？',
          '此操作将重置所有选手的检录状态和作品码绑定。',
          () => _clearAllCheckin(),
        );
        break;
      case 'clear_all_scores':
        _showConfirmDialog(
          '确定清除所有评分吗？',
          '此操作将删除所有选手的分数和评分照片。',
          () => _clearAllScores(),
        );
        break;
      case 'clear_all_data':
        _showConfirmDialog(
          '确定清除所有数据吗？',
          '此操作将删除所有选手数据，不可恢复！',
          () => _clearAllData(),
        );
        break;
      case 'deactivate':
        _showConfirmDialog(
          '确定解绑激活吗？',
          '解绑后需要重新选择激活文件才能使用。',
          () => _deactivate(),
        );
        break;
    }
  }

  void _showConfirmDialog(
    String title,
    String content,
    VoidCallback onConfirm,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllCheckin() async {
    final provider = context.read<ParticipantProvider>();
    try {
      for (final p in provider.participants) {
        if (p.checkStatus == 1 ||
            (p.workCode != null && p.workCode!.isNotEmpty)) {
          final updated = p.copyWith(checkStatus: 0, workCode: null);
          await provider.updateParticipant(updated);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已清除所有检录状态'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearAllScores() async {
    final provider = context.read<ParticipantProvider>();
    try {
      // 删除所有评分照片
      final evidenceDir = await _storageService.getEvidenceDirectory();
      final photoFiles = await _fileService.listFiles(
        evidenceDir,
        extension: '.jpg',
      );
      for (final filePath in photoFiles) {
        try {
          await _fileService.deleteFile(filePath);
        } catch (e) {
          debugPrint('删除照片失败: $filePath, $e');
        }
      }

      // 清除所有选手的评分数据
      for (final p in provider.participants) {
        if (p.score != null || p.evidenceImg != null) {
          final updated = p.copyWith(score: null, evidenceImg: null);
          await provider.updateParticipant(updated);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已清除所有评分和照片'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _clearAllData() async {
    try {
      await context.read<ParticipantProvider>().clearData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已清除所有数据'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deactivate() async {
    try {
      await _activationService.deactivate();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已解绑激活'), backgroundColor: Colors.green),
        );
        // 跳转到激活页面
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.activation, (route) => false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解绑失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
