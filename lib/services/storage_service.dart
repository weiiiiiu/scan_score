import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 负责路径管理和配置持久化
class StorageService {
  static const String _csvPathKey = 'csv_file_path';
  SharedPreferences? _prefs;

  // 初始化 SharedPreferences
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // 获取应用文档目录
  Future<Directory> getAppDocumentsDirectory() async {
    return await getApplicationDocumentsDirectory();
  }

  // 获取 CSV 工作副本路径
  Future<String> getWorkingCsvPath() async {
    final appDir = await getAppDocumentsDirectory();
    return '${appDir.path}/data.csv';
  }

  // 获取保存的 CSV 源文件路径（用户导入的原始文件路径）
  String? getSavedCsvPath() {
    return _prefs?.getString(_csvPathKey);
  }

  // 保存 CSV 源文件路径
  Future<bool> saveCsvPath(String path) async {
    if (_prefs == null) await init();
    return await _prefs!.setString(_csvPathKey, path);
  }

  // 清除保存的 CSV 路径
  Future<bool> clearCsvPath() async {
    if (_prefs == null) await init();
    return await _prefs!.remove(_csvPathKey);
  }

  // 获取评分照片存储目录
  Future<String> getEvidenceDirectory() async {
    final appDir = await getAppDocumentsDirectory();
    final evidenceDir = Directory('${appDir.path}/evidence');

    // 如果目录不存在则创建
    if (!await evidenceDir.exists()) {
      await evidenceDir.create(recursive: true);
    }

    return evidenceDir.path;
  }

  // 检查工作 CSV 文件是否存在
  Future<bool> workingCsvExists() async {
    final csvPath = await getWorkingCsvPath();
    return await File(csvPath).exists();
  }

  // 获取临时目录（用于临时文件）
  Future<Directory> getTempDirectory() async {
    return await getTemporaryDirectory();
  }

  // 清理所有数据（重置应用）
  Future<void> clearAllData() async {
    if (_prefs == null) await init();
    await _prefs!.clear();

    // 删除工作 CSV
    final csvPath = await getWorkingCsvPath();
    final csvFile = File(csvPath);
    if (await csvFile.exists()) {
      await csvFile.delete();
    }

    // 删除评分照片目录
    final evidenceDir = Directory(await getEvidenceDirectory());
    if (await evidenceDir.exists()) {
      await evidenceDir.delete(recursive: true);
    }
  }
}
