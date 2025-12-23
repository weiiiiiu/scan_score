import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/activation_service.dart';
import '../../config/routes.dart';

/// 激活页面
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  final ActivationService _activationService = ActivationService();
  bool _isActivating = false;
  String? _errorMessage;

  Future<void> _selectActivationFile() async {
    setState(() {
      _isActivating = true;
      _errorMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        setState(() => _isActivating = false);
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        setState(() {
          _isActivating = false;
          _errorMessage = '无法获取文件路径';
        });
        return;
      }

      final activationResult = await _activationService.activateWithFile(filePath);

      if (activationResult.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('激活成功'),
              backgroundColor: Colors.green,
            ),
          );
          // 导航到主界面
          Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
        }
      } else {
        setState(() {
          _isActivating = false;
          _errorMessage = activationResult.message;
        });
      }
    } catch (e) {
      setState(() {
        _isActivating = false;
        _errorMessage = '激活失败: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),

              // 图标
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_outline,
                  size: 60,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 32),

              // 标题
              Text(
                '软件未激活',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),

              // 说明文字
              Text(
                '请选择激活文件 (activation.key) 以激活软件',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 48),

              // 错误提示
              if (_errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // 激活按钮
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isActivating ? null : _selectActivationFile,
                  icon: _isActivating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.folder_open),
                  label: Text(_isActivating ? '正在激活...' : '选择激活文件'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // 底部提示
              Text(
                '如需获取激活文件，请联系管理员',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
