import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path/path.dart' as path;
import 'package:archive/archive.dart';
import '../../providers/participant_provider.dart';
import '../../services/storage_service.dart';
import '../../services/file_service.dart';

/// 导出界面
/// 提供 CSV 导出和数据统计功能
class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final StorageService _storageService = StorageService();
  final FileService _fileService = FileService();
  bool _isExporting = false;
  bool _isExportingPhotos = false;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ParticipantProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('导出数据'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 统计摘要卡片
            _buildStatsSummaryCard(provider),
            const SizedBox(height: 20),
            // 详细统计卡片
            _buildDetailedStatsCard(provider),
            const SizedBox(height: 20),
            // 导出操作卡片
            _buildExportCard(provider),
            const SizedBox(height: 20),
            // 导出评分照片卡片
            _buildExportPhotosCard(provider),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsSummaryCard(ParticipantProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.summarize, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '数据摘要',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    '总人数',
                    provider.totalCount.toString(),
                    Colors.blue,
                    Icons.people,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatBox(
                    '已检录',
                    provider.checkedInCount.toString(),
                    Colors.green,
                    Icons.check_circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatBox(
                    '未检录',
                    provider.uncheckedCount.toString(),
                    Colors.orange,
                    Icons.pending,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatBox(
                    '已评分',
                    provider.scoredCount.toString(),
                    Colors.purple,
                    Icons.star,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatBox(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(fontSize: 14, color: color.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedStatsCard(ParticipantProvider provider) {
    // 计算评分统计
    final scoredParticipants = provider.getScoredParticipants();
    double avgScore = 0;
    double maxScore = 0;
    double minScore = 10;

    if (scoredParticipants.isNotEmpty) {
      final scores = scoredParticipants.map((p) => p.score!).toList();
      avgScore = scores.reduce((a, b) => a + b) / scores.length;
      maxScore = scores.reduce((a, b) => a > b ? a : b);
      minScore = scores.reduce((a, b) => a < b ? a : b);
    }

    // 计算检录率
    final checkInRate = provider.totalCount > 0
        ? (provider.checkedInCount / provider.totalCount * 100)
        : 0.0;

    // 计算评分率
    final scoreRate = provider.totalCount > 0
        ? (provider.scoredCount / provider.totalCount * 100)
        : 0.0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  '详细统计',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildProgressStat('检录完成率', checkInRate, Colors.green),
            const SizedBox(height: 16),
            _buildProgressStat('评分完成率', scoreRate, Colors.purple),
            if (scoredParticipants.isNotEmpty) ...[
              const Divider(height: 32),
              _buildScoreStat('平均分数', avgScore),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildScoreStat('最高分', maxScore)),
                  Expanded(child: _buildScoreStat('最低分', minScore)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStat(String label, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              '${percentage.toStringAsFixed(1)}%',
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildScoreStat(String label, double score) {
    return Row(
      children: [
        Text('$label: ', style: TextStyle(color: Colors.grey.shade600)),
        Text(
          score.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildExportCard(ParticipantProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.file_download, color: Colors.deepOrange),
                SizedBox(width: 8),
                Text(
                  '导出选项',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '导出的 CSV 文件将包含所有选手数据，包括检录状态、作品码绑定、评分等信息。',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              '导出格式: 姓名,参赛编号,组别,头像名称,领队姓名,作品码,检录状态,分数,评分照片',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isExporting || !provider.hasData
                    ? null
                    : () => _exportData(provider),
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt),
                label: Text(_isExporting ? '正在导出...' : '导出 CSV 文件'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
            if (!provider.hasData)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  '没有数据可导出，请先导入 CSV 文件',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportData(ParticipantProvider provider) async {
    setState(() {
      _isExporting = true;
    });

    try {
      final path = await provider.exportData();

      if (mounted) {
        if (path != null) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              icon: const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 48,
              ),
              title: const Text('导出成功'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('文件已保存到:'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      path,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
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
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('导出取消或失败'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
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

  /// 构建导出评分照片卡片
  Widget _buildExportPhotosCard(ParticipantProvider provider) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.photo_library, color: Colors.blue),
                SizedBox(width: 8),
                Text(
                  '导出评分照片',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              '将所有评分照片打包为 ZIP 文件导出，照片命名格式为：作品码_分数.jpg',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isExportingPhotos || !provider.hasData
                    ? null
                    : () => _exportPhotos(),
                icon: _isExportingPhotos
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.photo_camera),
                label: Text(_isExportingPhotos ? '正在导出...' : '导出评分照片'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 导出评分照片
  Future<void> _exportPhotos() async {
    if (_isExportingPhotos) return;

    setState(() {
      _isExportingPhotos = true;
    });

    try {
      // 获取评分照片目录
      final evidenceDir = await _storageService.getEvidenceDirectory();
      final photoFiles = await _fileService.listFiles(
        evidenceDir,
        extension: '.jpg',
      );

      if (photoFiles.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('没有找到评分照片'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      // 显示导出选项对话框
      if (mounted) {
        _showExportOptionsDialog(photoFiles);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExportingPhotos = false;
        });
      }
    }
  }

  /// 显示导出选项对话框
  void _showExportOptionsDialog(List<String> photoFiles) {
    // 解析照片信息
    final photoInfoList = <Map<String, dynamic>>[];
    for (final filePath in photoFiles) {
      final fileName = path.basenameWithoutExtension(filePath);
      // 文件名格式: 作品码_分数（分数的小数点替换为下划线）
      // 例如: 88250001_85_5.jpg 表示作品码88250001，分数85.5
      final parts = fileName.split('_');
      if (parts.length >= 2) {
        final workCode = parts[0];
        // 分数部分可能是 "85_5" 格式，需要还原为 "85.5"
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

    // 按作品码排序
    photoInfoList.sort(
      (a, b) => (a['workCode'] as String).compareTo(b['workCode'] as String),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.photo_library,
                        color: Colors.blue,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '导出评分照片',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '共 ${photoInfoList.length} 张照片',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 照片列表
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(8),
                itemCount: photoInfoList.length,
                itemBuilder: (context, index) {
                  final info = photoInfoList[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(info['filePath']),
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
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
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            // 导出按钮
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _doExportPhotos(photoFiles);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('导出全部照片'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 执行导出照片
  Future<void> _doExportPhotos(List<String> photoFiles) async {
    setState(() {
      _isExportingPhotos = true;
    });

    // 显示进度对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 20),
            Text('正在准备导出 ${photoFiles.length} 张照片...'),
          ],
        ),
      ),
    );

    try {
      // 创建压缩文件
      final tempDir = await _storageService.getTempDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipFilePath = '${tempDir.path}/评分照片_$timestamp.zip';

      // 使用 archive 包创建 zip 文件
      final archive = Archive();

      for (final filePath in photoFiles) {
        final file = File(filePath);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final fileName = path.basename(filePath);
          archive.addFile(ArchiveFile(fileName, bytes.length, bytes));
        }
      }

      // 编码并保存 zip 文件
      final zipEncoder = ZipEncoder();
      final zipData = zipEncoder.encode(archive);
      final zipFile = File(zipFilePath);
      await zipFile.writeAsBytes(zipData);

      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      // 使用分享功能导出
      await Share.shareXFiles(
        [XFile(zipFilePath)],
        subject: '评分照片导出',
        text: '共 ${photoFiles.length} 张评分照片',
      );

      // 删除临时文件
      try {
        await File(zipFilePath).delete();
      } catch (_) {}
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
          _isExportingPhotos = false;
        });
      }
    }
  }
}
