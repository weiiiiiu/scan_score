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
    _controller?.dispose();
    _barcodeService.dispose();
    _scoreController.dispose();
    super.dispose();
  }

  // 生命周期监听：处理切后台
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;

    // App 切到后台或不活跃
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // App 回到前台，重新初始化相机
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMessage = '未检测到相机');
        return;
      }

      // 优先后置
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // Android 优化
      _controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _controller!.initialize();

      if (mounted) {
        // 如果当前是初始状态，初始化完直接进入扫描
        if (_state == ScoringState.initial) {
          _startScanning();
        } else {
          setState(() {}); // 仅刷新UI
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '相机初始化失败: $e');
      }
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

  // --- 业务逻辑 ---

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

  // --- UI 构建 ---

  @override
  Widget build(BuildContext context) {
    // 1. 添加 GestureDetector 点击空白收起键盘
    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: true, // 保持为 true，通过 ScrollView 解决溢出
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
    return Center(
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
            const CircularProgressIndicator(),
        ],
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
                const Center(child: CircularProgressIndicator()),
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
    final p = _currentParticipant!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.verified, size: 80, color: Colors.green),
            const SizedBox(height: 24),
            Text(
              p.name,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '编号: ${p.memberCode}',
              style: const TextStyle(fontSize: 18, color: Colors.grey),
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

  // --- 修改点：使用 SingleChildScrollView + 固定高度 解决溢出和扁平化问题 ---
  Widget _buildScoringView() {
    // 使用屏幕宽度的 4/3 作为相机高度，保持标准比例，防止被压扁
    final cameraHeight = MediaQuery.of(context).size.width * 1.33;

    return SingleChildScrollView(
      child: Column(
        children: [
          // 顶部信息
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  '${_currentParticipant?.name} (${_currentParticipant?.memberCode})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
          ),

          // 相机预览 - 固定高度，移除 Expanded
          SizedBox(
            width: double.infinity,
            height: cameraHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_controller != null && _controller!.value.isInitialized)
                  // 使用 FittedBox 确保填充且不拉伸
                  FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: _controller!.value.previewSize!.height,
                      height: _controller!.value.previewSize!.width,
                      child: CameraPreview(_controller!),
                    ),
                  )
                else
                  const Center(child: Text("相机未就绪")),

                // 拍照按钮
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: FloatingActionButton.large(
                      onPressed: _takePhoto,
                      backgroundColor: Colors.white,
                      child: const Icon(
                        Icons.camera,
                        size: 50,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 分数输入
          _buildScorePanel(),

          // 底部填充，确保键盘弹出时能滚动到底部
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // --- 修改点：同样使用 SingleChildScrollView 解决溢出 ---
  Widget _buildPhotoTakenView() {
    final imageHeight = MediaQuery.of(context).size.width * 1.33;

    return SingleChildScrollView(
      child: Column(
        children: [
          // 照片预览 - 固定高度
          SizedBox(
            width: double.infinity,
            height: imageHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_photoPath != null)
                  Image.file(File(_photoPath!), fit: BoxFit.cover),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: FloatingActionButton.small(
                    onPressed: _retakePhoto,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.refresh, color: Colors.black),
                  ),
                ),
              ],
            ),
          ),

          // 分数输入
          _buildScorePanel(),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _saveScore,
                icon: const Icon(Icons.check),
                label: const Text('确认保存'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
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

  Widget _buildScorePanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('请输入分数 (0-100)', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 10),
          SizedBox(
            width: 150,
            child: TextField(
              controller: _scoreController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(border: UnderlineInputBorder()),
              onChanged: _updateScoreFromInput,
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
