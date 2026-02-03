import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:provider/provider.dart';
import '../../config/routes.dart';
import '../../providers/participant_provider.dart';
import '../../providers/auth_provider.dart';
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
  bool _isScrolling = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFBBDEFB), Color(0xFFE3F2FD), Color(0xFFF5F5F5)],
          ),
        ),
        child: SafeArea(
          child: LoadingOverlay(
            isLoading: _isImporting,
            message: '正在导入...',
            child: Consumer<ParticipantProvider>(
              builder: (context, provider, child) {
                return Stack(
                  children: [
                    Column(
                      children: [
                        // 搜索栏
                        if (provider.hasData) _buildSearchBar(),

                        // 数据表格区域
                        Expanded(
                          child: provider.hasData
                              ? NotificationListener<ScrollNotification>(
                                  onNotification: (notification) {
                                    if (notification
                                        is ScrollStartNotification) {
                                      if (!_isScrolling) {
                                        setState(() => _isScrolling = true);
                                      }
                                    } else if (notification
                                        is ScrollEndNotification) {
                                      if (_isScrolling) {
                                        setState(() => _isScrolling = false);
                                      }
                                    }
                                    return false;
                                  },
                                  child: ParticipantDataTable(
                                    searchQuery: _searchQuery,
                                  ),
                                )
                              : _buildEmptyState(provider),
                        ),
                      ],
                    ),

                    // 底部功能按钮
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 200),
                        offset: _isScrolling ? const Offset(0, 1) : Offset.zero,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _isScrolling ? 0.0 : 1.0,
                          child: _buildBottomButtons(provider),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 构建底部功能按钮
  Widget _buildBottomButtons(ParticipantProvider provider) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LiquidGlass.withOwnLayer(
        settings: const LiquidGlassSettings(
          thickness: 12,
          blur: 25,
          glassColor: Color(0x18FFFFFF),
          lightIntensity: 1.1,
          ambientStrength: 0.6,
          saturation: 1.0,
        ),
        shape: LiquidRoundedSuperellipse(borderRadius: 28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 导入按钮
              Expanded(
                child: _DockIcon(
                  icon: Icons.upload_file,
                  label: '导入',
                  color: Colors.blue,
                  onPressed: () => _importCsv(provider),
                ),
              ),
              const SizedBox(width: 10),
              // 检录按钮
              Expanded(
                child: _DockIcon(
                  icon: Icons.qr_code_scanner,
                  label: '检录',
                  color: Colors.green,
                  onPressed: provider.hasData
                      ? () => _navigateToCheckin()
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              // 评分按钮
              Expanded(
                child: _DockIcon(
                  icon: Icons.star_rate,
                  label: '评分',
                  color: Colors.orange,
                  onPressed: provider.hasData
                      ? () => _navigateToScoring()
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              // 导出按钮
              Expanded(
                child: _DockIcon(
                  icon: Icons.download,
                  label: '导出',
                  color: Colors.teal,
                  onPressed: provider.hasData
                      ? () => _navigateToExport()
                      : null,
                ),
              ),
            ],
          ),
        ),
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
          hintText: '搜索',
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
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        onChanged: (value) {
          // 检查是否输入了管理密码，进入管理页面
          final authProvider = context.read<AuthProvider>();
          if (authProvider.verifyPassword(value)) {
            _searchController.clear();
            setState(() {
              _searchQuery = '';
            });
            _navigateToManagement();
            return;
          }
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

  /// 导入 CSV 文件（需要密码验证）
  Future<void> _importCsv(ParticipantProvider provider) async {
    final verified = await AuthDialog.show(context, title: '导入验证');
    if (!verified) return;

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

  /// 导航到检录页面（无需验证）
  void _navigateToCheckin() {
    Navigator.pushNamed(context, AppRoutes.checkin);
  }

  /// 导航到评分页面（无需验证）
  void _navigateToScoring() {
    Navigator.pushNamed(context, AppRoutes.scoring);
  }

  /// 导航到管理页面（通过搜索栏输入admin进入，无需密码）
  void _navigateToManagement() {
    Navigator.pushNamed(context, AppRoutes.management);
  }

  /// 导航到导出页面（需要验证）
  Future<void> _navigateToExport() async {
    final verified = await AuthDialog.show(context, title: '导出验证');

    if (verified && mounted) {
      Navigator.pushNamed(context, AppRoutes.export);
    }
  }
}

/// Dock图标组件
class _DockIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _DockIcon({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isEnabled = onPressed != null;
    final effectiveColor = isEnabled ? color : Colors.grey[400]!;

    return GestureDetector(
      onTap: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [effectiveColor.withValues(alpha: 0.9), effectiveColor],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: effectiveColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 6),
          // 标签
          Text(
            label,
            style: TextStyle(
              color: isEnabled ? Colors.black87 : Colors.grey,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
