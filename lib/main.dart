import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/storage_service.dart';
import 'services/file_service.dart';
import 'services/csv_service.dart';
import 'providers/participant_provider.dart';
import 'providers/auth_provider.dart';
import 'config/routes.dart';
import 'config/theme.dart';

void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务
  final storageService = StorageService();
  await storageService.init();

  final fileService = FileService();
  final csvService = CsvService(storageService, fileService);

  // 初始化 AuthProvider（加载自定义密码）
  final authProvider = AuthProvider();
  await authProvider.init();

  runApp(
    MyApp(
      storageService: storageService,
      fileService: fileService,
      csvService: csvService,
      authProvider: authProvider,
    ),
  );
}

class MyApp extends StatelessWidget {
  final StorageService storageService;
  final FileService fileService;
  final CsvService csvService;
  final AuthProvider authProvider;

  const MyApp({
    super.key,
    required this.storageService,
    required this.fileService,
    required this.csvService,
    required this.authProvider,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 身份验证 Provider（已初始化）
        ChangeNotifierProvider.value(value: authProvider),

        // 参赛者数据 Provider
        ChangeNotifierProvider(
          create: (_) =>
              ParticipantProvider(csvService, fileService, storageService),
          // 数据加载移到 SplashScreen 中进行
        ),
      ],
      child: MaterialApp(
        title: '检录评分系统',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        initialRoute: AppRoutes.splash,
        routes: AppRoutes.getRoutes(),
      ),
    );
  }
}
