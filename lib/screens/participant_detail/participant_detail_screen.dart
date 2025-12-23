import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/participant.dart';
import '../../providers/participant_provider.dart';

/// 参赛者详情编辑页面 - 所有字段可编辑
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

  late TextEditingController _memberCodeController;
  late TextEditingController _nameController;
  late TextEditingController _groupController;
  late TextEditingController _projectController;
  late TextEditingController _teamNameController;
  late TextEditingController _instructorController;
  late TextEditingController _workCodeController;
  late TextEditingController _rankController;

  late bool _isCheckedIn;
  bool _hasChanges = false;
  bool _isSaving = false;

  String? _memberCodeError;
  String? _workCodeError;

  @override
  void initState() {
    super.initState();
    final p = widget.participant;

    _memberCodeController = TextEditingController(text: p.memberCode)
      ..addListener(_onFieldChanged);
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
    _workCodeController = TextEditingController(text: p.workCode ?? '')
      ..addListener(_onFieldChanged);
    _rankController = TextEditingController(
      text: p.score != null ? p.score!.toInt().toString() : '',
    )..addListener(_onFieldChanged);

    _isCheckedIn = p.checkStatus == 1;
  }

  void _onFieldChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
    // 清除错误提示
    if (_memberCodeError != null || _workCodeError != null) {
      setState(() {
        _memberCodeError = null;
        _workCodeError = null;
      });
    }
  }

  @override
  void dispose() {
    _memberCodeController.dispose();
    _nameController.dispose();
    _groupController.dispose();
    _projectController.dispose();
    _teamNameController.dispose();
    _instructorController.dispose();
    _workCodeController.dispose();
    _rankController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final provider = context.read<ParticipantProvider>();
    final newMemberCode = _memberCodeController.text.trim();
    final newWorkCode = _workCodeController.text.trim();

    // 判重检查
    if (provider.isMemberCodeDuplicate(newMemberCode, widget.participant.id)) {
      setState(() {
        _memberCodeError = '参赛证号已存在';
      });
      return;
    }

    if (newWorkCode.isNotEmpty &&
        provider.isWorkCodeDuplicate(newWorkCode, widget.participant.id)) {
      setState(() {
        _workCodeError = '作品码已被使用';
      });
      return;
    }

    setState(() => _isSaving = true);

    try {
      final rankText = _rankController.text.trim();
      double? rank;
      if (rankText.isNotEmpty) {
        rank = double.tryParse(rankText);
      }

      final updated = widget.participant.copyWith(
        memberCode: newMemberCode,
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
        workCode: newWorkCode.isEmpty ? null : newWorkCode,
        checkStatus: _isCheckedIn ? 1 : 0,
        score: rank,
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
                // 头部卡片
                _buildHeaderCard(),
                const SizedBox(height: 24),

                // 基本信息
                _buildSectionTitle('基本信息'),
                const SizedBox(height: 12),
                _buildBasicInfoFields(),
                const SizedBox(height: 24),

                // 检录和评分信息
                _buildSectionTitle('检录和评分信息'),
                const SizedBox(height: 12),
                _buildScoringFields(),
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
                _nameController.text.isNotEmpty
                    ? _nameController.text[0]
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
                    _nameController.text.isEmpty ? '未填写' : _nameController.text,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ID: ${widget.participant.id}',
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

  Widget _buildBasicInfoFields() {
    return Column(
      children: [
        // 参赛证号 - 可编辑，判重
        TextFormField(
          controller: _memberCodeController,
          decoration: InputDecoration(
            labelText: '参赛证号',
            hintText: '请输入参赛证号',
            prefixIcon: const Icon(Icons.badge),
            helperText: '必填项，不可与其他选手重复',
            errorText: _memberCodeError,
          ),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return '参赛证号不能为空';
            }
            return null;
          },
          enabled: !_isSaving,
        ),
        const SizedBox(height: 16),

        // 姓名
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

        // 组别
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

        // 项目
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

        // 队名
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

        // 辅导员
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

  Widget _buildScoringFields() {
    return Card(
      color: Colors.grey[50],
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 作品码 - 可编辑，判重
            TextFormField(
              controller: _workCodeController,
              decoration: InputDecoration(
                labelText: '作品码',
                hintText: '请输入作品码',
                prefixIcon: const Icon(Icons.qr_code),
                helperText: '不可与其他选手重复',
                errorText: _workCodeError,
              ),
              enabled: !_isSaving,
            ),
            const SizedBox(height: 16),

            // 检录状态
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: Colors.grey),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '检录状态',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
                Switch(
                  value: _isCheckedIn,
                  onChanged: _isSaving
                      ? null
                      : (value) {
                          setState(() {
                            _isCheckedIn = value;
                            _hasChanges = true;
                          });
                        },
                ),
                Text(
                  _isCheckedIn ? '已检录' : '未检录',
                  style: TextStyle(
                    color: _isCheckedIn ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 名次
            TextFormField(
              controller: _rankController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '名次',
                hintText: '请输入名次（留空表示未评分）',
                prefixIcon: Icon(Icons.emoji_events),
                helperText: '输入整数，如 1、2、3',
              ),
              validator: (value) {
                if (value != null && value.trim().isNotEmpty) {
                  final parsed = int.tryParse(value.trim());
                  if (parsed == null || parsed < 1) {
                    return '请输入有效的名次（正整数）';
                  }
                }
                return null;
              },
              enabled: !_isSaving,
            ),

            // 照片路径（只读显示）
            if (widget.participant.evidenceImg != null &&
                widget.participant.evidenceImg!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.photo, color: Colors.grey),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '照片: ${widget.participant.evidenceImg!.split('/').last}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
