import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';

/// 身份验证对话框
/// 用于需要权限验证的操作（只需要密码）
class AuthDialog extends StatefulWidget {
  /// 对话框标题
  final String title;

  /// 验证成功后的回调
  final VoidCallback onSuccess;

  /// 是否需要超级管理员权限
  final bool superOnly;

  const AuthDialog({
    super.key,
    required this.title,
    required this.onSuccess,
    this.superOnly = false,
  });

  /// 显示验证对话框的便捷方法
  static Future<bool> show(
    BuildContext context, {
    String title = '身份验证',
    bool superOnly = false,
  }) async {
    bool verified = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AuthDialog(
        title: title,
        superOnly: superOnly,
        onSuccess: () {
          verified = true;
          Navigator.of(context).pop();
        },
      ),
    );

    return verified;
  }

  @override
  State<AuthDialog> createState() => _AuthDialogState();
}

class _AuthDialogState extends State<AuthDialog> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  void _verify() {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    bool isValid = authProvider.verifyPassword(
      _passwordController.text,
      superOnly: widget.superOnly,
    );

    if (isValid) {
      widget.onSuccess();
    } else {
      setState(() {
        _errorMessage = '密码错误，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return '请输入密码';
                }
                return null;
              },
              onFieldSubmitted: (_) => _verify(),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        ElevatedButton(onPressed: _verify, child: const Text('确认')),
      ],
    );
  }
}
