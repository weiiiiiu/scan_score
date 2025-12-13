import 'package:flutter/material.dart';
import '../screens/splash_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/checkin/checkin_screen.dart';
import '../screens/scoring/scoring_screen.dart';
import '../screens/management/management_screen.dart';
import '../screens/export/export_screen.dart';

/// 应用路由配置
class AppRoutes {
  // 路由名称常量
  static const String splash = '/';
  static const String dashboard = '/dashboard';
  static const String checkin = '/checkin';
  static const String scoring = '/scoring';
  static const String management = '/management';
  static const String export = '/export';

  /// 生成路由表
  static Map<String, WidgetBuilder> getRoutes() {
    return {
      splash: (context) => const SplashScreen(),
      dashboard: (context) => const DashboardScreen(),
      checkin: (context) => const CheckinScreen(),
      scoring: (context) => const ScoringScreen(),
      management: (context) => const ManagementScreen(),
      export: (context) => const ExportScreen(),
    };
  }

  /// 导航到指定路由
  static Future<T?> navigateTo<T>(BuildContext context, String routeName) {
    return Navigator.pushNamed<T>(context, routeName);
  }

  /// 替换当前路由
  static Future<T?> replaceTo<T>(BuildContext context, String routeName) {
    return Navigator.pushReplacementNamed<T, dynamic>(context, routeName);
  }

  /// 返回上一页
  static void goBack<T>(BuildContext context, [T? result]) {
    Navigator.pop(context, result);
  }

  /// 返回到首页
  static void goHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, dashboard, (route) => false);
  }
}
