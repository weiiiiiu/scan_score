import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../providers/participant_provider.dart';
import '../../widgets/auth_dialog.dart';
import '../../widgets/loading_overlay.dart';
import 'widgets/participant_data_table.dart';

/// Dashboard 首页
/// 展示数据概览、参赛者列表和功能入口
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isImporting = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('检录评分系统'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '刷新数据',
            onPressed: () {
              context.read<ParticipantProvider>().refresh();
            },
          ),
        ],
      ),
      body: LoadingOverlay(
        isLoading: _isImporting,
        message: '正在导入...',
        child: Consumer<ParticipantProvider>(
          builder: (context, provider, child) {
            return Column(
              children: [
                // 统计卡片区域
                _buildStatsSection(provider),

                // 搜索栏
                if (provider.hasData) _buildSearchBar(),

                // 数据表格区域
                Expanded(
                  child: provider.hasData
                      ? ParticipantDataTable(searchQuery: _searchQuery)
                      : _buildEmptyState(provider),
                ),

                // 底部功能按钮
                _buildBottomButtons(provider),
              ],
            );
          },
        ),
      ),
    );
  }

  /// 构建统计卡片区域
  Widget _buildStatsSection(ParticipantProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _StatCard(
              title: '总人数',
              value: provider.totalCount.toString(),
              icon: Icons.people,
              color: Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: '已检录',
              value: provider.checkedInCount.toString(),
              icon: Icons.check_circle,
              color: Colors.green,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: '未检录',
              value: provider.uncheckedCount.toString(),
              icon: Icons.pending,
              color: Colors.orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _StatCard(
              title: '已评分',
              value: provider.scoredCount.toString(),
              icon: Icons.star,
              color: Colors.purple,
            ),
          ),
        ],
      ),
    );
  }

  /// 构建搜索栏
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '搜索姓名、参赛编号或作品码...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[100],
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
      ),
    );
  }

  /// 构建空状态
  Widget _buildEmptyState(ParticipantProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载中...'),
          ],
        ),
      );
    }

    if (provider.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              provider.error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => provider.loadData(),
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 24),
          const Text(
            '暂无数据',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('请点击下方按钮导入 CSV 名单文件', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () => _importCsv(provider),
            icon: const Icon(Icons.upload_file),
            label: const Text('导入名单（CSV）'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建底部功能按钮
  Widget _buildBottomButtons(ParticipantProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // 导入按钮
            Expanded(
              child: _ActionButton(
                icon: Icons.upload_file,
                label: '导入名单',
                color: Colors.blue,
                onPressed: () => _importCsv(provider),
              ),
            ),
            const SizedBox(width: 12),
            // 检录按钮
            Expanded(
              child: _ActionButton(
                icon: Icons.qr_code_scanner,
                label: '检录',
                color: Colors.green,
                onPressed: provider.hasData ? () => _navigateToCheckin() : null,
              ),
            ),
            const SizedBox(width: 12),
            // 评分按钮
            Expanded(
              child: _ActionButton(
                icon: Icons.star_rate,
                label: '评分',
                color: Colors.orange,
                onPressed: provider.hasData ? () => _navigateToScoring() : null,
              ),
            ),
            const SizedBox(width: 12),
            // 管理按钮
            Expanded(
              child: _ActionButton(
                icon: Icons.edit_note,
                label: '管理',
                color: Colors.purple,
                onPressed: provider.hasData
                    ? () => _navigateToManagement()
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            // 导出按钮
            Expanded(
              child: _ActionButton(
                icon: Icons.download,
                label: '导出',
                color: Colors.teal,
                onPressed: provider.hasData ? () => _navigateToExport() : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 导入 CSV 文件
  Future<void> _importCsv(ParticipantProvider provider) async {
    setState(() {
      _isImporting = true;
    });

    try {
      final success = await provider.importCsv();
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('导入成功'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  /// 导航到检录页面（需要验证）
  Future<void> _navigateToCheckin() async {
    final verified = await AuthDialog.show(context, title: '检录验证');

    if (verified && mounted) {
      Navigator.pushNamed(context, AppRoutes.checkin);
    }
  }

  /// 导航到评分页面（无需验证）
  void _navigateToScoring() {
    Navigator.pushNamed(context, AppRoutes.scoring);
  }

  /// 导航到管理页面（需要超级管理员验证）
  Future<void> _navigateToManagement() async {
    final verified = await AuthDialog.show(
      context,
      title: '管理验证',
      superOnly: true,
    );

    if (verified && mounted) {
      Navigator.pushNamed(context, AppRoutes.management);
    }
  }

  /// 导航到导出页面（需要验证）
  Future<void> _navigateToExport() async {
    final verified = await AuthDialog.show(context, title: '导出验证');

    if (verified && mounted) {
      Navigator.pushNamed(context, AppRoutes.export);
    }
  }
}

/// 统计卡片组件
class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
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
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 功能按钮组件
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;

    return Material(
      color: isEnabled ? color : Colors.grey[300],
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: isEnabled ? Colors.white : Colors.grey[500],
                size: 28,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isEnabled ? Colors.white : Colors.grey[500],
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
