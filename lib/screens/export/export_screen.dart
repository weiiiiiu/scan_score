import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/participant_provider.dart';

/// 导出界面
/// 提供 CSV 导出和数据统计功能
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  bool _isExporting = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParticipantProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('导出数据'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 统计摘要卡片
            _buildStatsSummaryCard(provider),
            const SizedBox(height: 20),
            // 详细统计卡片
            _buildDetailedStatsCard(provider),
            const SizedBox(height: 20),
            // 分组统计卡片
            _buildGroupStatsCard(provider),
            const SizedBox(height: 20),
            // 导出操作卡片
            _buildExportCard(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSummaryCard(ParticipantProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.summarize, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '数据摘要',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    '总人数',
                    provider.totalCount.toString(),
                    Colors.blue,
                    Icons.people,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatBox(
                    '已检录',
                    provider.checkedInCount.toString(),
                    Colors.green,
                    Icons.check_circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    '未检录',
                    provider.uncheckedCount.toString(),
                    Colors.orange,
                    Icons.pending,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatBox(
                    '已评分',
                    provider.scoredCount.toString(),
                    Colors.purple,
                    Icons.star,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 14, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStatsCard(ParticipantProvider provider) {
    // 计算评分统计
    final scoredParticipants = provider.getScoredParticipants();
    double avgScore = 0;
    double maxScore = 0;
    double minScore = 10;

    if (scoredParticipants.isNotEmpty) {
      final scores = scoredParticipants.map((p) => p.score!).toList();
      avgScore = scores.reduce((a, b) => a + b) / scores.length;
      maxScore = scores.reduce((a, b) => a > b ? a : b);
      minScore = scores.reduce((a, b) => a < b ? a : b);
    }

    // 计算检录率
    final checkInRate = provider.totalCount > 0
        ? (provider.checkedInCount / provider.totalCount * 100)
        : 0.0;

    // 计算评分率
    final scoreRate = provider.totalCount > 0
        ? (provider.scoredCount / provider.totalCount * 100)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  '详细统计',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildProgressStat('检录完成率', checkInRate, Colors.green),
            const SizedBox(height: 16),
            _buildProgressStat('评分完成率', scoreRate, Colors.purple),
            if (scoredParticipants.isNotEmpty) ...[
              const Divider(height: 32),
              _buildScoreStat('平均分数', avgScore),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildScoreStat('最高分', maxScore)),
                  Expanded(child: _buildScoreStat('最低分', minScore)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStat(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildScoreStat(String label, double score) {
    return Row(
      children: [
        Text('$label: ', style: TextStyle(color: Colors.grey.shade600)),
        Text(
          score.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildGroupStatsCard(ParticipantProvider provider) {
    // 按组别统计
    final groupStats = <String, Map<String, int>>{};

    for (final p in provider.participants) {
      final group = p.group ?? '未分组';
      if (!groupStats.containsKey(group)) {
        groupStats[group] = {'total': 0, 'checkedIn': 0, 'scored': 0};
      }
      groupStats[group]!['total'] = groupStats[group]!['total']! + 1;
      if (p.checkStatus == 1) {
        groupStats[group]!['checkedIn'] = groupStats[group]!['checkedIn']! + 1;
      }
      if (p.score != null) {
        groupStats[group]!['scored'] = groupStats[group]!['scored']! + 1;
      }
    }

    final sortedGroups = groupStats.keys.toList()..sort();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.group_work, color: Colors.teal),
                SizedBox(width: 8),
                Text(
                  '分组统计',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (sortedGroups.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('暂无数据'),
                ),
              )
            else
              ...sortedGroups.map((group) {
                final stats = groupStats[group]!;
                return _buildGroupRow(
                  group,
                  stats['total']!,
                  stats['checkedIn']!,
                  stats['scored']!,
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupRow(String group, int total, int checkedIn, int scored) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 80,
            child: Text(
              group,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildGroupStat('总数', total, Colors.blue),
                _buildGroupStat('检录', checkedIn, Colors.green),
                _buildGroupStat('评分', scored, Colors.purple),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupStat(String label, int value, Color color) {
    return Column(
      children: [
        Text(
          value.toString(),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildExportCard(ParticipantProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.file_download, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text(
                  '导出选项',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '导出的 CSV 文件将包含所有选手数据，包括检录状态、作品码绑定、评分等信息。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '导出格式: 姓名,参赛编号,组别,头像名称,领队姓名,作品码,检录状态,分数,评分照片',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isExporting || !provider.hasData
                    ? null
                    : () => _exportData(provider),
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(_isExporting ? '正在导出...' : '导出 CSV 文件'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (!provider.hasData)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '没有数据可导出，请先导入 CSV 文件',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData(ParticipantProvider provider) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final path = await provider.exportData();

      if (mounted) {
        if (path != null) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 48,
              ),
              title: const Text('导出成功'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('文件已保存到:'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      path,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('导出取消或失败'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }
}
