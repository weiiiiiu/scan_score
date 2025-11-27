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

  runApp(
    MyApp(
      storageService: storageService,
      fileService: fileService,
      csvService: csvService,
    ),
  );
}

class MyApp extends StatelessWidget {
  final StorageService storageService;
  final FileService fileService;
  final CsvService csvService;

  const MyApp({
    super.key,
    required this.storageService,
    required this.fileService,
    required this.csvService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // 身份验证 Provider
        ChangeNotifierProvider(create: (_) => AuthProvider()),

        // 参赛者数据 Provider
        ChangeNotifierProvider(
          create: (_) =>
              ParticipantProvider(csvService, fileService, storageService)
                ..loadData(), // 自动加载数据
        ),
      ],
      child: MaterialApp(
        title: '检录评分系统',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        initialRoute: AppRoutes.dashboard,
        routes: AppRoutes.getRoutes(),
      ),
    );
  }
}
