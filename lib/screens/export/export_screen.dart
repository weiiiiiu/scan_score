import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
// 新增包
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';

import '../../providers/participant_provider.dart';
import '../../services/storage_service.dart';
import '../../services/file_service.dart';

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final StorageService _storageService = StorageService();
  final FileService _fileService = FileService();
  bool _isExporting = false;
  List<Map<String, dynamic>> _photoInfoList = [];

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  /// 检查读取权限并加载数据
  Future<void> _checkPermissionAndLoad() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;

      // Android 13+ (API 33) 读取图片需要 PHOTOS 权限
      if (sdkInt >= 33) {
        if (await Permission.photos.request().isGranted) {
          _loadPhotoInfo();
        }
      }
      // Android 12 及以下需要 STORAGE 权限
      else {
        if (await Permission.storage.request().isGranted) {
          _loadPhotoInfo();
        }
      }
    } else {
      _loadPhotoInfo();
    }
  }

  /// 加载照片信息
  Future<void> _loadPhotoInfo() async {
    try {
      final evidenceDir = await _storageService.getEvidenceDirectory();
      if (!await Directory(evidenceDir).exists()) {
        if (mounted) setState(() => _photoInfoList = []);
        return;
      }

      final photoFiles = await _fileService.listFiles(
        evidenceDir,
        extension: '.jpg',
      );

      final photoInfoList = <Map<String, dynamic>>[];
      for (final filePath in photoFiles) {
        final fileName = path.basenameWithoutExtension(filePath);
        final parts = fileName.split('_');
        if (parts.length >= 2) {
          final workCode = parts[0];
          String scoreStr;
          if (parts.length >= 3) {
            scoreStr = '${parts[1]}.${parts[2]}';
          } else {
            scoreStr = parts[1];
          }
          final score = double.tryParse(scoreStr);

          photoInfoList.add({
            'filePath': filePath,
            'fileName': path.basename(filePath),
            'workCode': workCode,
            'score': score,
            'scoreDisplay': score?.toStringAsFixed(1) ?? scoreStr,
          });
        }
      }

      photoInfoList.sort(
        (a, b) => (a['workCode'] as String).compareTo(b['workCode'] as String),
      );

      if (mounted) {
        setState(() {
          _photoInfoList = photoInfoList;
        });
      }
    } catch (e) {
      debugPrint('加载照片信息失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParticipantProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('导出数据'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissionAndLoad,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatsSummaryCard(provider),
          Expanded(
            child: _photoInfoList.isEmpty
                ? _buildEmptyPhotoState()
                : _buildPhotoList(),
          ),
          _buildExportButton(provider),
        ],
      ),
    );
  }

  Widget _buildStatsSummaryCard(ParticipantProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  '总人数',
                  provider.totalCount.toString(),
                  Colors.blue,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  '已检录',
                  provider.checkedInCount.toString(),
                  Colors.green,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  '已评分',
                  provider.scoredCount.toString(),
                  Colors.purple,
                ),
              ),
              Expanded(
                child: _buildStatItem(
                  '照片数',
                  _photoInfoList.length.toString(),
                  Colors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildEmptyPhotoState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无评分照片',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _photoInfoList.length,
      itemBuilder: (context, index) {
        final info = _photoInfoList[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(info['filePath']),
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(width: 60, height: 60, color: Colors.grey[200]),
              ),
            ),
            title: Text(
              '作品码: ${info['workCode']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('分数: ${info['scoreDisplay']}'),
            trailing: Text(
              info['fileName'],
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            onTap: () => _showPhotoPreview(info),
          ),
        );
      },
    );
  }

  void _showPhotoPreview(Map<String, dynamic> info) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppBar(
                title: Text('作品码: ${info['workCode']}'),
                automaticallyImplyLeading: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: Image.file(File(info['filePath']), fit: BoxFit.contain),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '分数: ${info['scoreDisplay']}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExportButton(ParticipantProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _isExporting || !provider.hasData
                ? null
                : () => _exportAll(provider),
            icon: _isExporting
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save_alt, size: 28),
            label: Text(
              _isExporting ? '正在打包...' : '导出数据 (pfxt.zip)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 核心导出逻辑：兼容 Android 10 ~ 16
  // ==========================================
  Future<void> _exportAll(ParticipantProvider provider) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('正在打包数据...'),
          ],
        ),
      ),
    );

    try {
      // 1. 生成 ZIP 到临时目录 (兼容所有版本，不需权限)
      final archive = Archive();

      // 添加 CSV (带 BOM 解决乱码)
      final csvContent = _generateCsv(provider.participants);
      final csvBytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csvContent)];
      archive.addFile(ArchiveFile('data.csv', csvBytes.length, csvBytes));

      // 添加照片
      final evidenceDir = await _storageService.getEvidenceDirectory();
      if (await Directory(evidenceDir).exists()) {
        final photoFiles = await _fileService.listFiles(
          evidenceDir,
          extension: '.jpg',
        );
        for (final filePath in photoFiles) {
          final f = File(filePath);
          if (await f.exists()) {
            final bytes = await f.readAsBytes();
            archive.addFile(
              ArchiveFile(path.basename(filePath), bytes.length, bytes),
            );
          }
        }
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData == null) throw Exception("压缩数据为空");

      final tempDir = await getTemporaryDirectory();
      final tempZipPath =
          '${tempDir.path}/pfxt_${DateTime.now().millisecondsSinceEpoch}.zip';
      final tempZipFile = File(tempZipPath);
      await tempZipFile.writeAsBytes(zipData);

      // 关闭进度条
      if (mounted) Navigator.of(context).pop();

      // 2. 根据安卓版本执行保存逻辑
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkInt = androidInfo.version.sdkInt;

        if (sdkInt < 30) {
          // Android 10 (SDK 29) 及以下：使用 FilePicker + 直接写入
          await _saveFileLegacy(tempZipFile);
        } else {
          // Android 11+ (SDK 30+)：使用 SAF 系统保存对话框
          await _saveFileModern(tempZipFile);
        }
      } else {
        // iOS 或其他平台逻辑 (暂按 Modern 处理)
        await _saveFileModern(tempZipFile);
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.of(context).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  /// 方案 A：Android 10 及以下 (直接文件操作)
  Future<void> _saveFileLegacy(File sourceFile) async {
    // 申请存储权限
    if (!await Permission.storage.request().isGranted) {
      throw Exception("请授予存储权限以导出文件");
    }

    // 选择文件夹
    final directory = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存位置',
    );
    if (directory == null) return;

    final targetPath =
        '$directory/pfxt_${DateTime.now().millisecondsSinceEpoch}.zip';
    await sourceFile.copy(targetPath);

    if (mounted) _showSuccessDialog(targetPath);
  }

  /// 方案 B：Android 11+ (调用系统保存界面)
  Future<void> _saveFileModern(File sourceFile) async {
    final params = SaveFileDialogParams(
      sourceFilePath: sourceFile.path,
      fileName: 'pfxt_${DateTime.now().millisecondsSinceEpoch}.zip',
    );

    // 这会弹出一个系统底部的保存框，用户可以选择下载目录或其他位置
    final filePath = await FlutterFileDialog.saveFile(params: params);

    if (filePath != null && mounted) {
      _showSuccessDialog("系统下载/文档目录");
    }
  }

  void _showSuccessDialog(String path) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: const Text('导出成功'),
        content: Text('文件已保存。\n($path)'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  String _generateCsv(List participants) {
    final rows = <List<dynamic>>[
      ['参赛证号', '姓名', '组别', '项目', '队名', '辅导员', '作品码', '检录状态', '分数', '照片路径'],
      ...participants.map((p) => p.toCsvRow()),
    ];
    return const ListToCsvConverter().convert(rows);
  }
}
