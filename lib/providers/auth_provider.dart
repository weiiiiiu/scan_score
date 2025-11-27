import 'package:flutter/foundation.dart';

/// 身份验证管理
/// 使用硬编码的密码进行简单验证（只需要输入密码）
class AuthProvider extends ChangeNotifier {
  // 硬编码的密码
  static const String _adminPassword = 'hlink';
  static const String _superPassword = 'hlink';

  /// 验证管理员密码
  bool verifyAdminPassword(String password) {
    return password == _adminPassword;
  }

  /// 验证超级管理员密码
  bool verifySuperPassword(String password) {
    return password == _superPassword;
  }

  /// 验证密码（支持两种级别）
  bool verifyPassword(String password, {bool superOnly = false}) {
    if (superOnly) {
      return password == _superPassword;
    }
    return password == _adminPassword || password == _superPassword;
  }

  /// 获取密码对应的权限级别
  String getPasswordLevel(String password) {
    if (password == _superPassword) {
      return '超级管理员';
    } else if (password == _adminPassword) {
      return '检录管理员';
    } else {
      return '未授权';
    }
  }
}
