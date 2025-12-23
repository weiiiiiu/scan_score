import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/participant_provider.dart';
import '../services/activation_service.dart';
import '../config/routes.dart';

/// 启动页面
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final ActivationService _activationService = ActivationService();

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // 延迟一帧确保 UI 已经渲染
    await Future.delayed(const Duration(milliseconds: 100));

    if (!mounted) return;

    // 检查激活状态
    final isActivated = await _activationService.isActivated();

    if (!mounted) return;

    if (!isActivated) {
      // 未激活，跳转到激活页面
      Navigator.of(context).pushReplacementNamed(AppRoutes.activation);
      return;
    }

    // 已激活，加载数据
    final provider = context.read<ParticipantProvider>();
    await Future.wait([
      provider.loadData(),
      Future.delayed(const Duration(milliseconds: 500)),
    ]);

    if (!mounted) return;

    // 导航到主界面
    Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 应用图标或 Logo
            Icon(
              Icons.qr_code_scanner,
              size: 80,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 24),
            // 应用名称
            Text(
              '检录评分系统',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 32),
            // 加载指示器
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              '正在加载...',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}
