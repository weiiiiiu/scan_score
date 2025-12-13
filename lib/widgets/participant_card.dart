import 'package:flutter/material.dart';
import '../models/participant.dart';

/// 参赛者信息卡片组件
/// 用于展示单个参赛者的详细信息
class ParticipantCard extends StatelessWidget {
  /// 参赛者数据
  final Participant participant;

  /// 点击回调
  final VoidCallback? onTap;

  /// 是否显示详细信息
  final bool showDetails;

  /// 是否紧凑模式
  final bool compact;

  const ParticipantCard({
    super.key,
    required this.participant,
    this.onTap,
    this.showDetails = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 2,
      margin: compact
          ? const EdgeInsets.symmetric(vertical: 4, horizontal: 8)
          : const EdgeInsets.all(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: compact
              ? const EdgeInsets.all(12)
              : const EdgeInsets.all(16),
          child: compact ? _buildCompactLayout(theme) : _buildFullLayout(theme),
        ),
      ),
    );
  }

  /// 紧凑布局
  Widget _buildCompactLayout(ThemeData theme) {
    return Row(
      children: [
        _buildAvatar(size: 40),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                participant.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '编号: ${participant.memberCode}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        _buildStatusBadge(),
      ],
    );
  }

  /// 完整布局
  Widget _buildFullLayout(ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAvatar(size: 60),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      participant.name,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildStatusBadge(),
                ],
              ),
              const SizedBox(height: 8),
              _buildInfoRow(Icons.badge, '参赛证号', participant.memberCode),
              if (participant.group != null)
                _buildInfoRow(Icons.group, '组别', participant.group!),
              if (participant.project != null)
                _buildInfoRow(Icons.emoji_events, '项目', participant.project!),
              if (participant.teamName != null)
                _buildInfoRow(Icons.groups, '队名', participant.teamName!),
              if (participant.instructorName != null)
                _buildInfoRow(Icons.person, '辅导员', participant.instructorName!),
              if (showDetails) ...[
                if (participant.workCode != null)
                  _buildInfoRow(Icons.qr_code, '作品码', participant.workCode!),
                if (participant.score != null)
                  _buildInfoRow(
                    Icons.star,
                    '分数',
                    participant.score!.toStringAsFixed(1),
                    valueColor: Colors.orange,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 构建头像
  Widget _buildAvatar({required double size}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: Icon(Icons.person, size: size * 0.6, color: Colors.grey[400]),
    );
  }

  /// 构建状态标签
  Widget _buildStatusBadge() {
    Color bgColor;
    String text;
    IconData icon;

    if (participant.score != null) {
      bgColor = Colors.green;
      text = '已评分';
      icon = Icons.check_circle;
    } else if (participant.checkStatus == 1) {
      bgColor = Colors.blue;
      text = '已检录';
      icon = Icons.verified;
    } else {
      bgColor = Colors.grey;
      text = '未检录';
      icon = Icons.pending;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bgColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: bgColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: bgColor,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建信息行
  Widget _buildInfoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}
