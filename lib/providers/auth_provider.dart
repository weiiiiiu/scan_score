import 'package:flutter/foundation.dart';

/// 简单密码验证
class AuthProvider extends ChangeNotifier {
  static const String _password = 'hlink';

  /// 验证密码
  bool verifyPassword(String password) {
    return password == _password;
  }
}
