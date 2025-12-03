import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/participant_provider.dart';
import '../../models/participant.dart';
import '../../services/storage_service.dart';
import '../../services/file_service.dart';

/// 管理界面
/// 提供数据编辑、选手信息修改功能（需要超级管理员权限）
class ManagementScreen extends StatefulWidget {
  const ManagementScreen({super.key});

  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  final StorageService _storageService = StorageService();
  final FileService _fileService = FileService();

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
                  _buildStatusChip('分数: ${participant.score}', Colors.purple),
              ],
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () => _showEditDialog(participant),
        ),
        isThreeLine: true,
        onTap: () => _showParticipantDetails(participant),
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

  void _showParticipantDetails(Participant participant) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: CircleAvatar(
                  radius: 40,
                  backgroundColor: participant.checkStatus == 1
                      ? Colors.green
                      : Colors.grey,
                  child: Text(
                    participant.name.isNotEmpty ? participant.name[0] : '?',
                    style: const TextStyle(fontSize: 32, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  participant.name,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildDetailRow('ID', participant.id.toString()),
              _buildDetailRow('参赛证号', participant.memberCode),
              _buildDetailRow('组别', participant.group ?? '未分组'),
              _buildDetailRow('项目', participant.project ?? '无'),
              _buildDetailRow('队名', participant.teamName ?? '无'),
              _buildDetailRow('辅导员', participant.instructorName ?? '无'),
              _buildDetailRow('作品码', participant.workCode ?? '未绑定'),
              _buildDetailRow(
                '检录状态',
                participant.checkStatus == 1 ? '已检录' : '未检录',
              ),
              _buildDetailRow(
                '分数',
                participant.score?.toStringAsFixed(1) ?? '未评分',
              ),
              _buildDetailRow('评分照片', participant.evidenceImg ?? '无'),
              // 显示评分照片
              if (participant.evidenceImg != null &&
                  participant.evidenceImg!.isNotEmpty &&
                  File(participant.evidenceImg!).existsSync()) ...[
                const SizedBox(height: 16),
                const Text(
                  '评分照片预览:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(participant.evidenceImg!),
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        height: 100,
                        color: Colors.grey.shade200,
                        child: const Center(child: Text('无法加载照片')),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _showEditDialog(participant);
                      },
                      icon: const Icon(Icons.edit),
                      label: const Text('编辑'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: const Text('关闭'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 16))),
        ],
      ),
    );
  }

  void _showEditDialog(Participant participant) {
    final workCodeController = TextEditingController(
      text: participant.workCode,
    );
    final scoreController = TextEditingController(
      text: participant.score?.toString() ?? '',
    );
    int checkStatus = participant.checkStatus;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑: ${participant.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: workCodeController,
                decoration: const InputDecoration(
                  labelText: '作品码',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: scoreController,
                decoration: const InputDecoration(
                  labelText: '分数 (0-100)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
              StatefulBuilder(
                builder: (context, setDialogState) => Row(
                  children: [
                    const Text('检录状态: '),
                    const Spacer(),
                    Switch(
                      value: checkStatus == 1,
                      onChanged: (value) {
                        setDialogState(() {
                          checkStatus = value ? 1 : 0;
                          // 取消检录时清空作品码
                          if (checkStatus == 0) {
                            workCodeController.clear();
                          }
                        });
                      },
                    ),
                    Text(checkStatus == 1 ? '已检录' : '未检录'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              // 验证分数
              double? score;
              if (scoreController.text.isNotEmpty) {
                score = double.tryParse(scoreController.text);
                if (score == null || score < 0 || score > 100) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('分数必须在 0-100 之间')),
                  );
                  return;
                }
              }

              // 检查分数是否改变，如果改变且有评分照片，需要重命名照片
              String? newEvidenceImg = participant.evidenceImg;
              final oldScore = participant.score;
              final workCode = workCodeController.text.isEmpty
                  ? participant.workCode
                  : workCodeController.text;

              if (score != oldScore &&
                  participant.evidenceImg != null &&
                  participant.evidenceImg!.isNotEmpty &&
                  workCode != null &&
                  workCode.isNotEmpty) {
                try {
                  final oldPath = participant.evidenceImg!;
                  if (await File(oldPath).exists()) {
                    // 构建新文件名: workCode_score.jpg
                    final scoreStr = score != null
                        ? (score == score.toInt()
                              ? score.toInt().toString()
                              : score.toStringAsFixed(1))
                        : 'noscore';
                    final evidenceDir = await _storageService
                        .getEvidenceDirectory();
                    final newFileName = '${workCode}_$scoreStr.jpg';
                    final newPath = '$evidenceDir/$newFileName';

                    // 重命名文件
                    await _fileService.renameFile(oldPath, newPath);
                    newEvidenceImg = newPath;
                  }
                } catch (e) {
                  debugPrint('重命名评分照片失败: $e');
                  // 继续执行，不影响其他数据更新
                }
              }

              final updated = participant.copyWith(
                workCode: workCodeController.text.isEmpty
                    ? null
                    : workCodeController.text,
                checkStatus: checkStatus,
                score: score,
                evidenceImg: newEvidenceImg,
              );

              try {
                await context.read<ParticipantProvider>().updateParticipant(
                  updated,
                );
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('保存成功'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('保存失败: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
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
}
