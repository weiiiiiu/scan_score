import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/participant.dart';
import '../../providers/participant_provider.dart';

/// 参赛者详情编辑页面
class ParticipantDetailScreen extends StatefulWidget {
  final Participant participant;

  const ParticipantDetailScreen({
    super.key,
    required this.participant,
  });

  @override
  State<ParticipantDetailScreen> createState() =>
      _ParticipantDetailScreenState();
}

class _ParticipantDetailScreenState extends State<ParticipantDetailScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _nameController;
  late TextEditingController _groupController;
  late TextEditingController _projectController;
  late TextEditingController _teamNameController;
  late TextEditingController _instructorController;

  bool _hasChanges = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.participant;

    _nameController = TextEditingController(text: p.name)
      ..addListener(_onFieldChanged);
    _groupController = TextEditingController(text: p.group ?? '')
      ..addListener(_onFieldChanged);
    _projectController = TextEditingController(text: p.project ?? '')
      ..addListener(_onFieldChanged);
    _teamNameController = TextEditingController(text: p.teamName ?? '')
      ..addListener(_onFieldChanged);
    _instructorController = TextEditingController(text: p.instructorName ?? '')
      ..addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _groupController.dispose();
    _projectController.dispose();
    _teamNameController.dispose();
    _instructorController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    try {
      final provider = context.read<ParticipantProvider>();
      final updated = widget.participant.copyWith(
        name: _nameController.text.trim(),
        group: _groupController.text.trim().isEmpty
            ? null
            : _groupController.text.trim(),
        project: _projectController.text.trim().isEmpty
            ? null
            : _projectController.text.trim(),
        teamName: _teamNameController.text.trim().isEmpty
            ? null
            : _teamNameController.text.trim(),
        instructorName: _instructorController.text.trim().isEmpty
            ? null
            : _instructorController.text.trim(),
      );

      await provider.updateParticipant(updated);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存成功'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) {
      return true;
    }

    final shouldPop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('您有未保存的修改，确定要离开吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('放弃'),
          ),
        ],
      ),
    );

    return shouldPop ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('参赛者详情'),
          actions: [
            if (_isSaving)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.save),
                onPressed: _hasChanges ? _saveChanges : null,
                tooltip: '保存',
              ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头部卡片 - 显示参赛者图标和证号
                _buildHeaderCard(),
                const SizedBox(height: 24),

                // 基本信息
                _buildSectionTitle('基本信息'),
                const SizedBox(height: 12),
                _buildEditableFields(),
                const SizedBox(height: 24),

                // 检录和评分信息（只读）
                _buildSectionTitle('检录和评分信息'),
                const SizedBox(height: 12),
                _buildReadOnlyInfo(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Text(
                widget.participant.name.isNotEmpty
                    ? widget.participant.name[0]
                    : '?',
                style: const TextStyle(
                  fontSize: 24,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.participant.name,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '参赛证号: ${widget.participant.memberCode}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  Widget _buildEditableFields() {
    return Column(
      children: [
        TextFormField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: '姓名',
            hintText: '请输入姓名',
            prefixIcon: Icon(Icons.person),
            helperText: '必填项',
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '姓名不能为空';
            }
            return null;
          },
          enabled: !_isSaving,
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: widget.participant.memberCode,
          decoration: const InputDecoration(
            labelText: '参赛证号',
            prefixIcon: Icon(Icons.badge),
            helperText: '不可修改',
          ),
          enabled: false,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _groupController,
          decoration: const InputDecoration(
            labelText: '组别',
            hintText: '请输入组别',
            prefixIcon: Icon(Icons.group),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _projectController,
          decoration: const InputDecoration(
            labelText: '项目',
            hintText: '请输入项目',
            prefixIcon: Icon(Icons.sports),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _teamNameController,
          decoration: const InputDecoration(
            labelText: '队名',
            hintText: '请输入队名',
            prefixIcon: Icon(Icons.people),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _instructorController,
          decoration: const InputDecoration(
            labelText: '辅导员',
            hintText: '请输入辅导员姓名',
            prefixIcon: Icon(Icons.person_outline),
          ),
          enabled: !_isSaving,
        ),
      ],
    );
  }

  Widget _buildReadOnlyInfo() {
    final p = widget.participant;
    final isCheckedIn = p.checkStatus == 1;
    final hasScore = p.score != null;

    return Card(
      color: Colors.grey[100],
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow(
              '检录状态',
              isCheckedIn ? '已检录' : '未检录',
              isCheckedIn ? Colors.green : Colors.orange,
            ),
            if (p.workCode != null && p.workCode!.isNotEmpty) ...[
              const Divider(height: 20),
              _buildInfoRow(
                '作品码',
                p.workCode!,
                Colors.blue,
              ),
            ],
            if (hasScore) ...[
              const Divider(height: 20),
              _buildInfoRow(
                '分数',
                p.score.toString(),
                Colors.purple,
              ),
            ],
            if (!isCheckedIn && !hasScore) ...[
              const SizedBox(height: 8),
              Text(
                '提示：检录和评分信息请在对应页面操作',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
