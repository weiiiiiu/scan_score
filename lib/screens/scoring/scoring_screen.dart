import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as path;
import '../../providers/participant_provider.dart';
import '../../services/barcode_service.dart';
import '../../services/storage_service.dart';
import '../../services/file_service.dart';
import '../../models/participant.dart';

enum ScoringState {
  initial, // 初始状态，等待相机就绪
  scanning, // 正在扫描作品码
  participantFound, // 找到选手，显示静态信息（相机可暂停）
  scoring, // 评分中（开启相机预览准备拍照）
  photoTaken, // 已拍照，显示照片预览
  completed, // 评分完成
}

class ScoringScreen extends StatefulWidget {
  const ScoringScreen({super.key});

  @override
  State<ScoringScreen> createState() => _ScoringScreenState();
}

class _ScoringScreenState extends State<ScoringScreen>
    with WidgetsBindingObserver {
  // 核心服务
  CameraController? _controller;
  final BarcodeService _barcodeService = BarcodeService();
  final StorageService _storageService = StorageService();
  final FileService _fileService = FileService();

  final TextEditingController _scoreController = TextEditingController();

  // 状态管理
  ScoringState _state = ScoringState.initial;
  Participant? _currentParticipant;
  double _score = 50.0;
  String? _photoPath;
  String? _savedPhotoPath;
  String? _errorMessage;
  bool _isInitializing = false; // 防止重复初始化

  // 扫描控制
  bool _isProcessing = false;
  String _scannedWorkCode = '';
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scoreController.text = _score.toStringAsFixed(1);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _barcodeService.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  Future<void> _disposeCamera() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      if (controller.value.isStreamingImages) {
        try {
          await controller.stopImageStream();
        } catch (_) {}
      }
      await controller.dispose();
    }
  }

  // 生命周期监听：处理切后台
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 相机未初始化时不处理
    if (_controller == null) return;

    if (state == AppLifecycleState.inactive) {
      // App 切到后台，释放相机
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      // App 回到前台，重新初始化
      if (_controller == null && !_isInitializing) {
        _initializeCamera();
      }
    }
  }

  Future<void> _initializeCamera() async {
    // 防止重复初始化
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      // 先释放旧的 controller
      await _disposeCamera();

      // 等待相机资源完全释放
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) return;

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMessage = '未检测到相机');
        return;
      }

      if (!mounted) return;

      // 优先后置
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Android 优化
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;

      // 如果当前是初始状态，初始化完直接进入扫描
      if (_state == ScoringState.initial) {
        // 稍微延迟再开始扫描
        await Future.delayed(const Duration(milliseconds: 70));
        if (mounted && _controller != null) {
          _startScanning();
        }
      } else {
        setState(() {}); // 仅刷新UI
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '相机初始化失败: $e');
      }
    } finally {
      _isInitializing = false;
    }
  }

  /// 开始扫描（开启流）
  void _startScanning() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_controller!.value.isStreamingImages) return;

    _lastScannedCode = null;
    _lastScanTime = null;

    setState(() {
      _state = ScoringState.scanning;
      _errorMessage = null;
    });

    try {
      _controller!.startImageStream((image) async {
        if (_isProcessing || _state != ScoringState.scanning) return;

        _isProcessing = true;
        try {
          final barcode = await _barcodeService.scanFromCameraImage(
            image,
            _controller!.description.sensorOrientation,
            _controller!.description.lensDirection == CameraLensDirection.front,
          );

          if (barcode != null && barcode.trim().isNotEmpty && mounted) {
            final trimmedCode = barcode.trim();
            final now = DateTime.now();

            // 防抖
            if (_lastScannedCode == trimmedCode &&
                _lastScanTime != null &&
                now.difference(_lastScanTime!).inMilliseconds < 2000) {
              return;
            }

            _lastScannedCode = trimmedCode;
            _lastScanTime = now;

            await _stopScanning();
            _handleWorkCodeScanned(trimmedCode);
          }
        } catch (e) {
          debugPrint('Scan error: $e');
        } finally {
          _isProcessing = false;
        }
      });
    } catch (e) {
      debugPrint("Stream error: $e");
    }
  }

  /// 停止扫描
  Future<void> _stopScanning() async {
    if (_controller != null && _controller!.value.isStreamingImages) {
      try {
        await _controller!.stopImageStream();
      } catch (e) {
        debugPrint("Stop stream error: $e");
      }
    }
    if (mounted && _state == ScoringState.scanning) {
      setState(() {
        _state = ScoringState.initial;
      });
    }
  }

  /// 处理扫描结果
  void _handleWorkCodeScanned(String workCode) {
    if (workCode.isEmpty) {
      setState(() {
        _errorMessage = '条码内容为空';
        _state = ScoringState.initial;
      });
      return;
    }

    final provider = context.read<ParticipantProvider>();
    final participant = provider.findByWorkCode(workCode);

    setState(() {
      _scannedWorkCode = workCode;
      if (participant != null) {
        // 检查是否已评分
        if (participant.score != null) {
          _errorMessage = '该作品已评分: ${participant.score!.toStringAsFixed(1)}分';
          _currentParticipant = null;
          _state = ScoringState.initial;
          return;
        }
        _currentParticipant = participant;
        _score = 50.0;
        _scoreController.text = _score.toStringAsFixed(1);
        _savedPhotoPath = participant.evidenceImg;
        _photoPath = null;
        _state = ScoringState.participantFound;
        _errorMessage = null;
      } else {
        _errorMessage = '未找到作品码: $workCode';
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
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      if (_controller!.value.isTakingPicture) return;

      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
        await Future.delayed(const Duration(milliseconds: 50));
      }

      final xFile = await _controller!.takePicture();

      if (mounted) {
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

  void _updateScoreFromInput(String value) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      if (parsed > 100) {
        _score = 100.0;
        _scoreController.text = '100';
        _scoreController.selection = TextSelection.fromPosition(
          const TextPosition(offset: 3),
        );
      } else if (parsed < 0) {
        _score = 0.0;
        _scoreController.text = '0';
        _scoreController.selection = TextSelection.fromPosition(
          const TextPosition(offset: 1),
        );
      } else {
        _score = parsed;
      }
    }
  }

  Future<void> _saveScore() async {
    if (_currentParticipant == null) return;

    final provider = context.read<ParticipantProvider>();
    final workCode = _currentParticipant!.workCode ?? _scannedWorkCode;

    if (workCode.isEmpty) {
      _showSnack('作品码不能为空', Colors.red);
      return;
    }

    final hasNewPhoto = _photoPath != null && _photoPath!.isNotEmpty;
    final hasExistingPhoto =
        _savedPhotoPath != null && _savedPhotoPath!.isNotEmpty;

    if (!hasNewPhoto && !hasExistingPhoto) {
      _showSnack('请先拍照后再保存评分', Colors.orange);
      return;
    }

    try {
      String finalPhotoPath = '';
      if (hasNewPhoto) {
        finalPhotoPath = await _saveAndRenamePhoto(workCode, _score);
      } else if (hasExistingPhoto) {
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
        _showSnack('评分保存成功!', Colors.green);

        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _resetState();
        });
      }
    } catch (e) {
      if (mounted) _showSnack('保存失败: $e', Colors.red);
    }
  }

  Future<String> _saveAndRenamePhoto(String workCode, double score) async {
    final evidenceDir = await _storageService.getEvidenceDirectory();
    final scoreStr = score.toStringAsFixed(1).replaceAll('.', '_');
    final newFileName = '${workCode}_$scoreStr.jpg';
    final newPath = path.join(evidenceDir, newFileName);

    await _deleteOldPhotosForWorkCode(evidenceDir, workCode);
    await _fileService.copyFile(_photoPath!, newPath);

    _fileService.deleteFile(_photoPath!).catchError((_) {});

    return newPath;
  }

  Future<String> _renameExistingPhoto(
    String oldPath,
    String workCode,
    double score,
  ) async {
    final evidenceDir = await _storageService.getEvidenceDirectory();
    final scoreStr = score.toStringAsFixed(1).replaceAll('.', '_');
    final newFileName = '${workCode}_$scoreStr.jpg';
    final newPath = path.join(evidenceDir, newFileName);

    if (oldPath == newPath) return oldPath;

    if (await _fileService.fileExists(oldPath)) {
      try {
        await _fileService.renameFile(oldPath, newPath);
        return newPath;
      } catch (e) {
        debugPrint('Rename failed: $e');
        return oldPath;
      }
    }
    return oldPath;
  }

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
      debugPrint('Delete old photos error: $e');
    }
  }

  void _resetState() {
    _lastScannedCode = null;
    _lastScanTime = null;

    if (_controller != null && _controller!.value.isStreamingImages) {
      _controller!.stopImageStream().catchError((e) {});
    }

    setState(() {
      _state = ScoringState.scanning;
      _currentParticipant = null;
      _score = 50.0;
      _scoreController.text = '50.0';
      _photoPath = null;
      _savedPhotoPath = null;
      _errorMessage = null;
      _scannedWorkCode = '';
    });

    _startScanning();
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. 添加 GestureDetector 点击空白收起键盘
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('评分'),
          centerTitle: true,
          actions: [
            if (_state != ScoringState.initial &&
                _state != ScoringState.scanning)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _resetState,
                tooltip: '重新开始',
              ),
          ],
        ),
        body: _buildBody(),
      ),
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

  Widget _buildInitialView() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_errorMessage != null)
              Column(
                children: [
                  Icon(Icons.error, size: 80, color: Colors.red[300]),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _initializeCamera,
                    child: const Text('继续评分'),
                  ),
                ],
              )
            else
              Column(
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _isInitializing ? '正在初始化相机...' : '等待相机就绪...',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScanningView() {
    return Column(
      children: [
        Expanded(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null && _controller!.value.isInitialized)
                CameraPreview(_controller!)
              else
                Container(
                  color: Colors.black87,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 16),
                        Text(
                          _isInitializing ? '正在初始化相机...' : '等待相机就绪...',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blueAccent, width: 2),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const Positioned(
                bottom: 60,
                left: 0,
                right: 0,
                child: Center(
                  child: Text(
                    '扫描作品码',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(24),
          child: OutlinedButton.icon(
            onPressed: _showManualInputDialog,
            icon: const Icon(Icons.keyboard),
            label: const Text('手动输入作品码'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildParticipantFoundView() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            Text(
              '作品码: $_scannedWorkCode',
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 40),
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
                  child: ElevatedButton.icon(
                    onPressed: _enterScoringMode,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('开始评分'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- 相机全屏 + 分数输入绝对定位 ---
  Widget _buildScoringView() {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 相机预览 - 全屏
          if (_controller != null && _controller!.value.isInitialized)
            ClipRect(
              child: OverflowBox(
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _controller!.value.previewSize!.height,
                    height: _controller!.value.previewSize!.width,
                    child: CameraPreview(_controller!),
                  ),
                ),
              ),
            )
          else
            Container(
              color: Colors.black87,
              child: const Center(
                child: Text("相机未就绪", style: TextStyle(color: Colors.white70)),
              ),
            ),

          // 顶部信息 - 绝对定位
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: Colors.blue.withValues(alpha: 0.9),
              child: Row(
                children: [
                  const Icon(Icons.qr_code, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    '作品码: $_scannedWorkCode',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 底部分数输入区域 - 绝对定位
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '请输入分数 (0-100)',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _scoreController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        border: UnderlineInputBorder(),
                      ),
                      onChanged: _updateScoreFromInput,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 拍照按钮 - 中间偏下
          Positioned(
            bottom: 160,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.large(
                onPressed: _takePhoto,
                backgroundColor: Colors.white,
                child: const Icon(Icons.camera, size: 50, color: Colors.blue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- 照片预览全屏 + 分数输入绝对定位 ---
  Widget _buildPhotoTakenView() {
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 照片预览 - 全屏
          if (_photoPath != null)
            Image.file(File(_photoPath!), fit: BoxFit.cover)
          else
            Container(color: Colors.black),

          // 重拍按钮 - 右上角
          Positioned(
            top: 16,
            right: 16,
            child: FloatingActionButton.small(
              onPressed: _retakePhoto,
              backgroundColor: Colors.white,
              child: const Icon(Icons.refresh, color: Colors.black),
            ),
          ),

          // 底部分数输入 + 保存按钮 - 绝对定位
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '请输入分数 (0-100)',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 150,
                    child: TextField(
                      controller: _scoreController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        border: UnderlineInputBorder(),
                      ),
                      onChanged: _updateScoreFromInput,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saveScore,
                      icon: const Icon(Icons.check),
                      label: const Text('确认保存'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.task_alt, size: 100, color: Colors.green),
          const SizedBox(height: 20),
          const Text('评分保存成功', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 10),
          Text(
            '${_score.toStringAsFixed(1)}分',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

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
          onSubmitted: (val) {
            Navigator.pop(ctx);
            _handleWorkCodeScanned(val.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleWorkCodeScanned(controller.text.trim());
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}
