import 'package:flutter/foundation.dart';

/// 密码验证
class AuthProvider extends ChangeNotifier {
  static const String _password = 'admin';

  /// 验证密码
  bool verifyPassword(String password) {
    return password == _password;
  }
}
