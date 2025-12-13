import 'dart:io';
import 'dart:isolate';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/participant.dart';
import 'storage_service.dart';
import 'file_service.dart';

/// CSV 文件读写服务
/// 负责 CSV 文件的导入、导出、读取和保存
class CsvService {
  final StorageService _storageService;
  final FileService _fileService;

  CsvService(this._storageService, this._fileService);

  /// 从指定路径加载 CSV 文件 (使用 Isolate 在后台线程解析)
  Future<List<Participant>> loadCsv(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('CSV 文件不存在: $filePath');
    }

    final csvString = await file.readAsString();

    return await Isolate.run(() => _parseCsvInIsolate(csvString));
  }

  static List<Participant> _parseCsvInIsolate(String csvString) {
    final List<List<dynamic>> rows = const CsvToListConverter().convert(
      csvString,
    );

    // 跳过表头，从第二行开始解析
    if (rows.length <= 1) {
      return [];
    }

    final participants = <Participant>[];
    for (int i = 1; i < rows.length; i++) {
      try {
        // 跳过空行
        if (rows[i].isEmpty ||
            rows[i].every((cell) => cell.toString().trim().isEmpty)) {
          continue;
        }
        participants.add(Participant.fromCsvRow(rows[i], rowIndex: i));
      } catch (e) {
        // 跳过错误行，继续解析
      }
    }

    return participants;
  }

  /// 保存参赛者数据到 CSV 文件 (使用 Isolate 在后台线程生成)
  Future<void> saveCsv(String filePath, List<Participant> participants) async {
    final csvString = await Isolate.run(
      () => _generateCsvInIsolate(participants),
    );

    final dir = File(filePath).parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    // 写入文件
    await File(filePath).writeAsString(csvString);
  }

  static String _generateCsvInIsolate(List<Participant> participants) {
    // 构建 CSV 数据（包含表头）
    // 表头: 参赛证号,姓名,组别,项目,队名,辅导员,作品码,检录状态,分数,评分照片
    final rows = <List<dynamic>>[
      ['参赛证号', '姓名', '组别', '项目', '队名', '辅导员', '作品码', '检录状态', '分数', '评分照片'],
      ...participants.map((p) => p.toCsvRow()),
    ];

    // 转换为 CSV 字符串
    return const ListToCsvConverter().convert(rows);
  }

  /// 导入 CSV 文件（用户选择文件）
  /// 返回导入的文件路径，失败返回 null
  Future<String?> importCsv() async {
    try {
      // 使用 file_picker 让用户选择 CSV 文件
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        return null; // 用户取消选择
      }

      final pickedFile = result.files.first;
      if (pickedFile.path == null) {
        throw Exception('无法获取文件路径');
      }

      final sourcePath = pickedFile.path!;

      // 验证文件是否可以被解析
      final participants = await loadCsv(sourcePath);
      if (participants.isEmpty) {
        throw Exception('CSV 文件为空或格式不正确');
      }

      // 复制到应用工作目录
      final workingPath = await _storageService.getWorkingCsvPath();
      await _fileService.copyFile(sourcePath, workingPath);

      // 保存源文件路径
      await _storageService.saveCsvPath(sourcePath);

      return sourcePath;
    } catch (e) {
      debugPrint('导入 CSV 失败: $e');
      rethrow;
    }
  }

  /// 导出 CSV 文件（用户选择导出位置）
  /// 返回导出的文件路径，失败返回 null
  Future<String?> exportCsv(List<Participant> participants) async {
    try {
      // 使用 file_picker 让用户选择导出目录
      final dirPath = await FilePicker.platform.getDirectoryPath();

      if (dirPath == null) {
        return null; // 用户取消选择
      }

      // 生成导出文件名（带时间戳）
      final now = DateTime.now();
      final timestamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
      final exportFileName = '比赛成绩_$timestamp';
      final exportDir = '$dirPath/$exportFileName';

      // 创建导出目录
      await _fileService.createDirectory(exportDir);

      // 保存 CSV 文件
      final csvPath = '$exportDir/data.csv';
      await saveCsv(csvPath, participants);

      // 复制评分照片
      final evidenceDir = await _storageService.getEvidenceDirectory();
      final destEvidenceDir = '$exportDir/evidence';

      // 检查 evidence 目录是否存在且有文件
      if (await _fileService.directoryExists(evidenceDir)) {
        final files = await _fileService.listFiles(evidenceDir);
        if (files.isNotEmpty) {
          await _fileService.copyDirectory(evidenceDir, destEvidenceDir);
        }
      }

      return exportDir;
    } catch (e) {
      debugPrint('导出 CSV 失败: $e');
      rethrow;
    }
  }

  // 从工作目录加载 CSV
  Future<List<Participant>> loadWorkingCsv() async {
    final workingPath = await _storageService.getWorkingCsvPath();
    return await loadCsv(workingPath);
  }

  // 保存到工作目录
  Future<void> saveWorkingCsv(List<Participant> participants) async {
    final workingPath = await _storageService.getWorkingCsvPath();
    await saveCsv(workingPath, participants);
  }

  // 检查工作 CSV 是否存在
  Future<bool> hasWorkingCsv() async {
    return await _storageService.workingCsvExists();
  }
}
