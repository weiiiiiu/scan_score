import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../../providers/participant_provider.dart';
import '../../services/camera_service.dart';
import '../../services/barcode_service.dart';
import '../../services/storage_service.dart';
import '../../services/file_service.dart';
import '../../models/participant.dart';

/// 评分状态枚举
enum ScoringState {
  initial, // 初始状态，等待扫描作品码
  scanning, // 正在扫描
  participantFound, // 找到选手，显示信息
  scoring, // 评分中（拍照、调分）
  photoTaken, // 已拍照
  completed, // 评分完成
}

class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key});

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen> {
  final CameraService _cameraService = CameraService();
  final BarcodeService _barcodeService = BarcodeService();
  final StorageService _storageService = StorageService();
  final FileService _fileService = FileService();
  final TextEditingController _scoreController = TextEditingController();

  ScoringState _state = ScoringState.initial;
  Participant? _currentParticipant;
  double _score = 50.0; // 默认分数
  String? _photoPath; // 临时拍照路径
  String? _savedPhotoPath; // 最终保存的照片路径
  String? _errorMessage;
  bool _isProcessing = false;
  String _scannedWorkCode = '';
  String? _lastScannedCode; // 上一次扫描到的条码，用于防止重复识别
  DateTime? _lastScanTime; // 上一次扫描时间

  @override
  void initState() {
    super.initState();
    _scoreController.text = _score.toStringAsFixed(1);
    _initializeCamera();
  }

  @override
  void dispose() {
    _stopScanning();
    _cameraService.dispose();
    _barcodeService.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraService.initialize();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '相机初始化失败: $e';
        });
      }
    }
  }

  /// 开始扫描作品码
  Future<void> _startScanning() async {
    if (!_cameraService.isInitialized) return;

    // 清除上次扫描的条码缓存，准备扫描新条码
    _lastScannedCode = null;
    _lastScanTime = null;

    setState(() {
      _state = ScoringState.scanning;
      _errorMessage = null;
    });

    await _cameraService.startImageStream((image) async {
      if (_isProcessing || _state != ScoringState.scanning) return;

      _isProcessing = true;
      try {
        final barcode = await _barcodeService.scanFromCameraImage(
          image,
          _cameraService.sensorOrientation,
          _cameraService.isFrontCamera,
        );

        // 确保条形码内容非null且非空
        if (barcode != null && barcode.trim().isNotEmpty && mounted) {
          final trimmedCode = barcode.trim();
          final now = DateTime.now();

          // 防止重复识别同一个条码（2秒内不重复处理同一个条码）
          if (_lastScannedCode == trimmedCode &&
              _lastScanTime != null &&
              now.difference(_lastScanTime!).inMilliseconds < 2000) {
            return;
          }

          _lastScannedCode = trimmedCode;
          _lastScanTime = now;

          await _cameraService.stopImageStream();
          _handleWorkCodeScanned(trimmedCode);
        }
      } catch (e) {
        debugPrint('扫描错误: $e');
      } finally {
        _isProcessing = false;
      }
    });
  }

  /// 停止扫描
  Future<void> _stopScanning() async {
    await _cameraService.stopImageStream();
    if (mounted) {
      setState(() {
        if (_state == ScoringState.scanning) {
          _state = ScoringState.initial;
        }
      });
    }
  }

  /// 处理扫描到的作品码
  void _handleWorkCodeScanned(String workCode) {
    // 确保作品码非空
    if (workCode.isEmpty) {
      setState(() {
        _errorMessage = '扫描到的条形码内容为空';
        _state = ScoringState.initial;
      });
      return;
    }

    final provider = context.read<ParticipantProvider>();
    final participant = provider.findByWorkCode(workCode);

    setState(() {
      _scannedWorkCode = workCode;
      if (participant != null) {
        _currentParticipant = participant;
        // 如果有之前的分数，使用之前的分数
        _score = participant.score ?? 50.0;
        _scoreController.text = _score.toStringAsFixed(1);
        _savedPhotoPath = participant.evidenceImg;
        _photoPath = null; // 清除临时照片路径
        _state = ScoringState.participantFound;
        _errorMessage = null;
      } else {
        _errorMessage = '未找到作品码为"$workCode"的选手';
        _currentParticipant = null;
        _state = ScoringState.initial;
      }
    });
  }

  /// 进入评分模式
  void _enterScoringMode() {
    setState(() {
      _state = ScoringState.scoring;
    });
  }

  /// 拍照
  Future<void> _takePhoto() async {
    if (!_cameraService.isInitialized) return;

    try {
      final xFile = await _cameraService.takePicture();
      if (xFile != null && mounted) {
        setState(() {
          _photoPath = xFile.path;
          _state = ScoringState.photoTaken;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('拍照失败: $e')));
      }
    }
  }

  /// 重拍
  void _retakePhoto() {
    setState(() {
      _photoPath = null;
      _state = ScoringState.scoring;
    });
  }

  /// 更新分数（从输入框）
  void _updateScoreFromInput(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null && parsed >= 0 && parsed <= 100) {
      _score = parsed;
    }
  }

  /// 保存评分
  Future<void> _saveScore() async {
    if (_currentParticipant == null) return;

    final provider = context.read<ParticipantProvider>();
    final workCode = _currentParticipant!.workCode ?? _scannedWorkCode;

    // 确保作品码非空
    if (workCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('作品码不能为空'), backgroundColor: Colors.red),
      );
      return;
    }

    // 必须有照片才能保存评分
    final hasNewPhoto = _photoPath != null && _photoPath!.isNotEmpty;
    final hasExistingPhoto =
        _savedPhotoPath != null && _savedPhotoPath!.isNotEmpty;

    if (!hasNewPhoto && !hasExistingPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先拍照后再保存评分'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      String finalPhotoPath = '';

      // 处理照片：如果有新拍的照片，保存并重命名
      if (hasNewPhoto) {
        finalPhotoPath = await _saveAndRenamePhoto(workCode, _score);
      } else if (hasExistingPhoto) {
        // 如果没有新照片但有旧照片，需要重命名（因为分数可能变了）
        finalPhotoPath = await _renameExistingPhoto(
          _savedPhotoPath!,
          workCode,
          _score,
        );
      }

      await provider.submitScore(workCode, _score, finalPhotoPath);

      if (mounted) {
        setState(() {
          _state = ScoringState.completed;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '评分保存成功！选手: ${_currentParticipant!.name}, 分数: $_score',
            ),
            backgroundColor: Colors.green,
          ),
        );

        // 延迟后重置状态
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          _resetState();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// 保存并重命名新拍的照片
  /// 命名格式: 作品码_分数.jpg
  Future<String> _saveAndRenamePhoto(String workCode, double score) async {
    final evidenceDir = await _storageService.getEvidenceDirectory();
    final scoreStr = score.toStringAsFixed(1).replaceAll('.', '_');
    final newFileName = '${workCode}_$scoreStr.jpg';
    final newPath = path.join(evidenceDir, newFileName);

    // 删除可能存在的旧照片（同一作品码的）
    await _deleteOldPhotosForWorkCode(evidenceDir, workCode);

    // 复制新照片到目标位置
    await _fileService.copyFile(_photoPath!, newPath);

    // 删除临时照片
    try {
      await _fileService.deleteFile(_photoPath!);
    } catch (e) {
      debugPrint('删除临时照片失败: $e');
    }

    return newPath;
  }

  /// 重命名已存在的照片（分数更新时）
  Future<String> _renameExistingPhoto(
    String oldPath,
    String workCode,
    double score,
  ) async {
    final evidenceDir = await _storageService.getEvidenceDirectory();
    final scoreStr = score.toStringAsFixed(1).replaceAll('.', '_');
    final newFileName = '${workCode}_$scoreStr.jpg';
    final newPath = path.join(evidenceDir, newFileName);

    // 如果路径相同，不需要重命名
    if (oldPath == newPath) {
      return oldPath;
    }

    // 检查旧照片是否存在
    if (await _fileService.fileExists(oldPath)) {
      try {
        // 重命名文件
        await _fileService.renameFile(oldPath, newPath);
        return newPath;
      } catch (e) {
        debugPrint('重命名照片失败: $e');
        return oldPath;
      }
    }

    return oldPath;
  }

  /// 删除同一作品码的旧照片
  Future<void> _deleteOldPhotosForWorkCode(
    String evidenceDir,
    String workCode,
  ) async {
    try {
      final files = await _fileService.listFiles(
        evidenceDir,
        extension: '.jpg',
      );
      for (final filePath in files) {
        final fileName = path.basenameWithoutExtension(filePath);
        if (fileName.startsWith('${workCode}_')) {
          await _fileService.deleteFile(filePath);
        }
      }
    } catch (e) {
      debugPrint('删除旧照片失败: $e');
    }
  }

  /// 重置状态
  void _resetState() {
    // 清除条码缓存
    _lastScannedCode = null;
    _lastScanTime = null;

    setState(() {
      _state = ScoringState.initial;
      _currentParticipant = null;
      _score = 50.0;
      _scoreController.text = '50.0';
      _photoPath = null;
      _savedPhotoPath = null;
      _errorMessage = null;
      _scannedWorkCode = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('评分'),
        centerTitle: true,
        actions: [
          if (_state != ScoringState.initial)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _resetState,
              tooltip: '重新开始',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case ScoringState.initial:
        return _buildInitialView();
      case ScoringState.scanning:
        return _buildScanningView();
      case ScoringState.participantFound:
        return _buildParticipantFoundView();
      case ScoringState.scoring:
        return _buildScoringView();
      case ScoringState.photoTaken:
        return _buildPhotoTakenView();
      case ScoringState.completed:
        return _buildCompletedView();
    }
  }

  /// 初始界面
  Widget _buildInitialView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner, size: 100, color: Colors.blue),
          const SizedBox(height: 24),
          const Text(
            '评分模块',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            '扫描作品码开始评分',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _cameraService.isInitialized ? _startScanning : null,
            icon: const Icon(Icons.camera_alt),
            label: const Text('开始扫描'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              textStyle: const TextStyle(fontSize: 18),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _showManualInputDialog,
            icon: const Icon(Icons.edit),
            label: const Text('手动输入作品码'),
          ),
        ],
      ),
    );
  }

  /// 扫描界面
  Widget _buildScanningView() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              // 相机预览
              if (_cameraService.isInitialized &&
                  _cameraService.controller != null)
                SizedBox(
                  width: double.infinity,
                  child: CameraPreview(_cameraService.controller!),
                )
              else
                const Center(child: CircularProgressIndicator()),

              // 扫描框
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue, width: 3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    children: [
                      // 四角装饰
                      ...List.generate(4, (index) {
                        final isTop = index < 2;
                        final isLeft = index % 2 == 0;
                        return Positioned(
                          top: isTop ? 0 : null,
                          bottom: isTop ? null : 0,
                          left: isLeft ? 0 : null,
                          right: isLeft ? null : 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              border: Border(
                                top: isTop
                                    ? const BorderSide(
                                        color: Colors.blue,
                                        width: 4,
                                      )
                                    : BorderSide.none,
                                bottom: isTop
                                    ? BorderSide.none
                                    : const BorderSide(
                                        color: Colors.blue,
                                        width: 4,
                                      ),
                                left: isLeft
                                    ? const BorderSide(
                                        color: Colors.blue,
                                        width: 4,
                                      )
                                    : BorderSide.none,
                                right: isLeft
                                    ? BorderSide.none
                                    : const BorderSide(
                                        color: Colors.blue,
                                        width: 4,
                                      ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              // 提示文字
              Positioned(
                bottom: 50,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  color: Colors.black54,
                  child: const Text(
                    '将作品码放入框内扫描',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 底部按钮
        Container(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _stopScanning,
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showManualInputDialog,
                  icon: const Icon(Icons.edit),
                  label: const Text('手动输入'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 找到选手界面
  Widget _buildParticipantFoundView() {
    final participant = _currentParticipant!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // 选手信息卡片
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Icon(Icons.check_circle, size: 60, color: Colors.green),
                  const SizedBox(height: 16),
                  const Text(
                    '找到选手',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  _buildInfoRow('姓名', participant.name),
                  _buildInfoRow('参赛编号', participant.memberCode),
                  _buildInfoRow('组别', participant.group ?? '未分组'),
                  _buildInfoRow('领队', participant.leaderName ?? '无'),
                  _buildInfoRow(
                    '作品码',
                    participant.workCode ?? _scannedWorkCode,
                  ),
                  _buildInfoRow(
                    '检录状态',
                    participant.checkStatus == 1 ? '已检录' : '未检录',
                  ),
                  if (participant.score != null)
                    _buildInfoRow('当前分数', participant.score!.toString()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 操作按钮
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _resetState,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _enterScoringMode,
                  icon: const Icon(Icons.star),
                  label: const Text('开始评分'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 评分界面（拍照+调分）
  Widget _buildScoringView() {
    return Column(
      children: [
        // 顶部选手信息
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Row(
            children: [
              const Icon(Icons.person, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                '${_currentParticipant!.name} (${_currentParticipant!.memberCode})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // 相机预览（拍照区域）
        Expanded(
          flex: 2,
          child: Stack(
            children: [
              if (_cameraService.isInitialized &&
                  _cameraService.controller != null)
                SizedBox(
                  width: double.infinity,
                  child: CameraPreview(_cameraService.controller!),
                )
              else
                const Center(child: CircularProgressIndicator()),

              // 拍照按钮
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _takePhoto,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: Colors.blue, width: 4),
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 40,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // 分数调节区域
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                '评分',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _scoreController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.blue.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.blue,
                        width: 3,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  onChanged: _updateScoreFromInput,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '分数范围: 0 - 100',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        // 底部按钮
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _state = ScoringState.participantFound;
                    });
                  },
                  child: const Text('返回'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saveScore,
                  icon: const Icon(Icons.save),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  label: const Text('保存评分'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 拍照完成界面
  Widget _buildPhotoTakenView() {
    return Column(
      children: [
        // 顶部选手信息
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.green.shade50,
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                '${_currentParticipant!.name} - 已拍照',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        // 照片预览
        Expanded(
          flex: 2,
          child: _photoPath != null
              ? Image.file(File(_photoPath!), fit: BoxFit.contain)
              : const Center(child: Text('照片加载失败')),
        ),
        // 分数输入区域
        Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const Text(
                '评分',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _scoreController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.green.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.green,
                        width: 2,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.green,
                        width: 2,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: Colors.green,
                        width: 3,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                  ),
                  onChanged: _updateScoreFromInput,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '分数范围: 0 - 100',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        // 底部按钮
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retakePhoto,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重拍'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _saveScore,
                  icon: const Icon(Icons.save),
                  label: const Text('保存评分'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 完成界面
  Widget _buildCompletedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 100, color: Colors.green),
          const SizedBox(height: 24),
          const Text(
            '评分完成！',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${_currentParticipant?.name ?? ''} - ${_score.toStringAsFixed(1)} 分',
            style: const TextStyle(fontSize: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 手动输入作品码对话框
  void _showManualInputDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('输入作品码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入作品码',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) {
            final trimmedValue = value.trim();
            if (trimmedValue.isNotEmpty) {
              Navigator.pop(ctx);
              _handleWorkCodeScanned(trimmedValue);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final trimmedValue = controller.text.trim();
              if (trimmedValue.isNotEmpty) {
                Navigator.pop(ctx);
                _handleWorkCodeScanned(trimmedValue);
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
