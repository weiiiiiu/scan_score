import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../providers/participant_provider.dart';
import '../../services/storage_service.dart';
import '../../services/file_service.dart';

/// 导出界面
/// 提供 CSV 和评分照片打包导出功能
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
    _loadPhotoInfo();
  }

  /// 加载照片信息
  Future<void> _loadPhotoInfo() async {
    try {
      final evidenceDir = await _storageService.getEvidenceDirectory();
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
            onPressed: _loadPhotoInfo,
            tooltip: '刷新',
          ),
        ],
      ),
      body: Column(
        children: [
          // 统计摘要
          _buildStatsSummaryCard(provider),

          // 照片预览列表
          Expanded(
            child: _photoInfoList.isEmpty
                ? _buildEmptyPhotoState()
                : _buildPhotoList(),
          ),

          // 底部导出按钮
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
          const SizedBox(height: 8),
          Text(
            '评分时拍摄的照片会在这里显示',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
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
                errorBuilder: (_, _, _) => Container(
                  width: 60,
                  height: 60,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image),
                ),
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
            Image.file(
              File(info['filePath']),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Container(
                height: 200,
                color: Colors.grey.shade200,
                child: const Center(child: Icon(Icons.broken_image, size: 64)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    '分数: ${info['scoreDisplay']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '文件名: ${info['fileName']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
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
            color: Colors.black.withValues(alpha: 0.1),
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
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.download, size: 28),
            label: Text(
              _isExporting ? '正在导出...' : '导出数据 (pfxt.zip)',
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

  /// 导出全部数据（CSV + 照片）为 pfxt.zip
  Future<void> _exportAll(ParticipantProvider provider) async {
    if (_isExporting) return;

    setState(() {
      _isExporting = true;
    });

    // 显示进度对话框
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
      // 创建压缩文件
      final archive = Archive();

      // 1. 添加 CSV 文件（带 UTF-8 BOM 防止中文乱码）
      final csvContent = _generateCsv(provider.participants);
      // UTF-8 BOM: 0xEF, 0xBB, 0xBF
      final bom = [0xEF, 0xBB, 0xBF];
      final csvUtf8Bytes = utf8.encode(csvContent);
      final csvBytes = [...bom, ...csvUtf8Bytes];
      archive.addFile(ArchiveFile('data.csv', csvBytes.length, csvBytes));

      // 2. 添加所有评分照片
      final evidenceDir = await _storageService.getEvidenceDirectory();
      final photoFiles = await _fileService.listFiles(
        evidenceDir,
        extension: '.jpg',
      );

      for (final filePath in photoFiles) {
        final file = File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fileName = path.basename(filePath);
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        }
      }

      // 3. 编码为 zip
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);

      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 4. 让用户选择保存目录
      final selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择导出文件夹',
      );

      if (selectedDirectory == null) {
        // 用户取消了选择
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('已取消导出')));
        }
        return;
      }

      // 显示保存进度对话框
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 20),
                Text('正在保存文件...'),
              ],
            ),
          ),
        );
      }

      final zipPath = '$selectedDirectory/pfxt.zip';
      final zipFile = File(zipPath);
      await zipFile.writeAsBytes(zipData);

      // 关闭保存进度对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 显示成功对话框
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            title: const Text('导出成功'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('文件已保存到:'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    zipPath,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '包含 data.csv 和 ${photoFiles.length} 张评分照片',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
              ],
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
        });
      }
    }
  }

  /// 生成 CSV 内容
  String _generateCsv(List participants) {
    final rows = <List<dynamic>>[
      ['姓名', '参赛编号', '组别', '头像名称', '领队姓名', '作品码', '检录状态', '分数', '评分照片'],
      ...participants.map((p) => p.toCsvRow()),
    ];
    return const ListToCsvConverter().convert(rows);
  }
}
