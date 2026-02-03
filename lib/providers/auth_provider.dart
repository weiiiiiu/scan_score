import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 密码验证
class AuthProvider extends ChangeNotifier {
  /// 超级密码（永远有效）
  static const String _superPassword = 'hlink12138';

  /// 自定义密码存储 key
  static const String _customPasswordKey = 'custom_admin_password';

  /// 自定义密码（默认与超级密码相同）
  String _customPassword = _superPassword;

  SharedPreferences? _prefs;

  /// 初始化，加载保存的自定义密码
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    final savedPassword = _prefs?.getString(_customPasswordKey);
    debugPrint('AuthProvider.init: savedPassword = "$savedPassword"');
    _customPassword = savedPassword ?? _superPassword;
    debugPrint('AuthProvider.init: _customPassword = "$_customPassword"');
    notifyListeners();
  }

  /// 验证密码（超级密码或自定义密码都可以通过）
  bool verifyPassword(String password) {
    debugPrint('verifyPassword: input="$password", super="$_superPassword", custom="$_customPassword"');
    final result = password == _superPassword || password == _customPassword;
    debugPrint('verifyPassword: result=$result');
    return result;
  }

  /// 获取当前自定义密码
  String get customPassword => _customPassword;

  /// 设置自定义密码
  Future<bool> setCustomPassword(String newPassword) async {
    debugPrint('setCustomPassword: newPassword="$newPassword"');
    if (newPassword.isEmpty) {
      return false;
    }

    _prefs ??= await SharedPreferences.getInstance();
    final success = await _prefs!.setString(_customPasswordKey, newPassword);
    debugPrint('setCustomPassword: save success=$success');

    if (success) {
      _customPassword = newPassword;
      debugPrint('setCustomPassword: _customPassword updated to "$_customPassword"');
      notifyListeners();
    }

    return success;
  }

  /// 重置自定义密码为默认值
  Future<bool> resetCustomPassword() async {
    return await setCustomPassword(_superPassword);
  }
}
