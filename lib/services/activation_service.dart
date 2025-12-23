import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

/// 激活文件服务
/// 负责检查激活状态、验证激活文件
class ActivationService {
  static const String _activationFileName = 'activation.key';
  static const String _isActivatedKey = 'is_activated';
  static const String _activationPathKey = 'activation_path';

  // 固定密钥用于验证激活文件
  static const String _secretKey = 'scan_score_wsm_license_2024';

  SharedPreferences? _prefs;

  /// 初始化
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 获取预期的激活文件签名
  String get _expectedSignature {
    final data = 'scan_score_license_$_secretKey';
    return sha256.convert(utf8.encode(data)).toString().substring(0, 32).toUpperCase();
  }

  /// 检查是否已激活
  Future<bool> isActivated() async {
    await init();

    // 先检查SharedPreferences中的激活状态
    final isActivated = _prefs?.getBool(_isActivatedKey) ?? false;
    if (!isActivated) return false;

    // 验证激活文件是否仍然存在且有效
    final activationPath = _prefs?.getString(_activationPathKey);
    if (activationPath == null) return false;

    return await _verifyActivationFile(activationPath);
  }

  /// 验证激活文件
  Future<bool> _verifyActivationFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final content = await file.readAsString();
      return content.trim().toUpperCase() == _expectedSignature;
    } catch (e) {
      return false;
    }
  }

  /// 使用激活文件激活
  Future<ActivationResult> activateWithFile(String filePath) async {
    await init();

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ActivationResult(success: false, message: '激活文件不存在');
      }

      final content = await file.readAsString();
      if (content.trim().toUpperCase() != _expectedSignature) {
        return ActivationResult(success: false, message: '激活文件无效');
      }

      // 复制激活文件到应用目录
      final appDir = await getApplicationDocumentsDirectory();
      final targetPath = '${appDir.path}/$_activationFileName';
      await file.copy(targetPath);

      // 保存激活状态
      await _prefs?.setBool(_isActivatedKey, true);
      await _prefs?.setString(_activationPathKey, targetPath);

      return ActivationResult(success: true, message: '激活成功');
    } catch (e) {
      return ActivationResult(success: false, message: '激活失败: $e');
    }
  }

  /// 取消激活（用于换绑）
  Future<void> deactivate() async {
    await init();

    // 删除激活文件
    final activationPath = _prefs?.getString(_activationPathKey);
    if (activationPath != null) {
      try {
        final file = File(activationPath);
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }

    // 清除激活状态
    await _prefs?.setBool(_isActivatedKey, false);
    await _prefs?.remove(_activationPathKey);
  }

  /// 获取激活文件应包含的内容（用于调试/生成工具）
  String getExpectedFileContent() {
    return _expectedSignature;
  }
}

/// 激活结果
class ActivationResult {
  final bool success;
  final String message;

  ActivationResult({required this.success, required this.message});
}
