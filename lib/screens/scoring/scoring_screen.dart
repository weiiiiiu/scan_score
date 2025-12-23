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
  readyToScore, // 找到选手，显示名次信息，准备拍照
  photoTaken, // 已拍照，预览确认
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

  // 状态管理
  ScoringState _state = ScoringState.initial;
  Participant? _currentParticipant;
  String? _photoPath;
  String? _errorMessage;
  bool _isInitializing = false;
  bool _isSaving = false;

  // 扫描控制
  bool _isProcessing = false;
  String _scannedWorkCode = '';
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeCamera();
    _barcodeService.dispose();
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null) return;

    if (state == AppLifecycleState.inactive) {
      _disposeCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_isInitializing) {
        _initializeCamera();
      }
    }
  }

  Future<void> _initializeCamera() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      await _disposeCamera();
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted) return;

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMessage = '未检测到相机');
        return;
      }

      if (!mounted) return;

      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

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

      if (_state == ScoringState.initial) {
        await Future.delayed(const Duration(milliseconds: 70));
        if (mounted && _controller != null) {
          _startScanning();
        }
      } else {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '相机初始化失败: $e');
      }
    } finally {
      _isInitializing = false;
    }
  }

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
        // 检查是否已评分（已有名次）
        if (participant.score != null) {
          _errorMessage = '该作品已评为第 ${participant.score!.toInt()} 名';
          _currentParticipant = null;
          _state = ScoringState.initial;
          return;
        }
        _currentParticipant = participant;
        _photoPath = null;
        _state = ScoringState.readyToScore;
        _errorMessage = null;
      } else {
        _errorMessage = '未找到作品码: $workCode';
        _currentParticipant = null;
        _state = ScoringState.initial;
      }
    });
  }

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败: $e')),
        );
      }
    }
  }

  void _retakePhoto() {
    setState(() {
      _photoPath = null;
      _state = ScoringState.readyToScore;
    });
  }

  Future<void> _saveRank() async {
    if (_currentParticipant == null || _photoPath == null || _isSaving) return;

    setState(() => _isSaving = true);

    final provider = context.read<ParticipantProvider>();
    final workCode = _currentParticipant!.workCode ?? _scannedWorkCode;
    final rank = provider.getCurrentRank();

    try {
      // 保存照片并重命名
      final finalPhotoPath = await _savePhoto(workCode, rank);

      // 提交名次
      await provider.submitRank(workCode, finalPhotoPath);

      if (mounted) {
        setState(() {
          _state = ScoringState.completed;
          _isSaving = false;
        });
        _showSnack('第 $rank 名 保存成功!', Colors.green);

        // 1秒后自动返回扫描
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) _resetState();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('保存失败: $e', Colors.red);
      }
    }
  }

  Future<String> _savePhoto(String workCode, int rank) async {
    final evidenceDir = await _storageService.getEvidenceDirectory();
    final newFileName = '${workCode}_$rank.jpg';
    final newPath = path.join(evidenceDir, newFileName);

    // 删除该作品码的旧照片
    await _deleteOldPhotosForWorkCode(evidenceDir, workCode);

    // 复制新照片
    await _fileService.copyFile(_photoPath!, newPath);

    // 删除临时照片
    _fileService.deleteFile(_photoPath!).catchError((_) {});

    return newPath;
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
      _photoPath = null;
      _errorMessage = null;
      _scannedWorkCode = '';
      _isSaving = false;
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('评分'),
        centerTitle: true,
        actions: [
          if (_state != ScoringState.initial && _state != ScoringState.scanning)
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
      case ScoringState.readyToScore:
        return _buildReadyToScoreView();
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
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
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
              // 显示当前将评第几名
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: Consumer<ParticipantProvider>(
                    builder: (context, provider, _) {
                      final rank = provider.getCurrentRank();
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          '下一个: 第 $rank 名',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    },
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

  Widget _buildReadyToScoreView() {
    final provider = context.watch<ParticipantProvider>();
    final rank = provider.getCurrentRank();

    return Stack(
      fit: StackFit.expand,
      children: [
        // 相机预览
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

        // 中间大号名次显示
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '正在评',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 24,
                  ),
                ),
                Text(
                  '第 $rank 名',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 底部拍照按钮
        Positioned(
          bottom: 40,
          left: 0,
          right: 0,
          child: Column(
            children: [
              FloatingActionButton.large(
                onPressed: _takePhoto,
                backgroundColor: Colors.white,
                child: const Icon(Icons.camera_alt, size: 50, color: Colors.blue),
              ),
              const SizedBox(height: 12),
              const Text(
                '点击拍照',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                ),
              ),
            ],
          ),
        ),

        // 取消按钮
        Positioned(
          bottom: 40,
          left: 30,
          child: FloatingActionButton(
            heroTag: 'cancel',
            onPressed: _resetState,
            backgroundColor: Colors.white.withValues(alpha: 0.9),
            child: const Icon(Icons.close, color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _buildPhotoTakenView() {
    final provider = context.watch<ParticipantProvider>();
    final rank = provider.getCurrentRank();

    return Stack(
      fit: StackFit.expand,
      children: [
        // 照片预览
        if (_photoPath != null)
          Image.file(File(_photoPath!), fit: BoxFit.cover)
        else
          Container(color: Colors.black),

        // 顶部名次显示
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.7),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Text(
                    '第 $rank 名',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // 底部操作按钮
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.8),
                  Colors.transparent,
                ],
              ),
            ),
            child: Row(
              children: [
                // 重拍按钮
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving ? null : _retakePhoto,
                    icon: const Icon(Icons.refresh),
                    label: const Text('重拍'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // 确认保存按钮
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveRank,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSaving ? '保存中...' : '确认保存'),
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
        ),
      ],
    );
  }

  Widget _buildCompletedView() {
    // 获取刚才保存的名次（当前名次-1）
    final provider = context.watch<ParticipantProvider>();
    final savedRank = provider.getCurrentRank() - 1;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.task_alt, size: 100, color: Colors.green),
          const SizedBox(height: 20),
          const Text('保存成功', style: TextStyle(fontSize: 24)),
          const SizedBox(height: 10),
          Text(
            '第 $savedRank 名',
            style: const TextStyle(
              fontSize: 48,
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
