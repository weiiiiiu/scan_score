import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../models/participant.dart';
import '../../providers/participant_provider.dart';
import '../../services/barcode_service.dart';
import '../../services/camera_service.dart';

/// 检录状态
enum CheckinState {
  initial, // 初始状态
  scanningMember, // 扫描选手码
  memberScanned, // 选手码已扫描，显示选手信息
  scanningWork, // 扫描作品码
  completed, // 检录完成
}

/// 检录页面
class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final CameraService _cameraService = CameraService();
  final BarcodeService _barcodeService = BarcodeService();

  CheckinState _state = CheckinState.initial;
  String? _scannedMemberCode;
  Participant? _currentParticipant;
  String? _scannedWorkCode;
  String? _errorMessage;
  bool _isProcessing = false;
  String? _lastScannedCode; // 上一次扫描到的条码，用于防止重复识别
  DateTime? _lastScanTime; // 上一次扫描时间

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _cameraService.dispose();
    _barcodeService.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    final success = await _cameraService.initialize();
    if (success && mounted) {
      setState(() {
        _state = CheckinState.scanningMember;
      });
      _startScanning();
    } else if (mounted) {
      setState(() {
        _errorMessage = '相机初始化失败，请检查权限设置';
      });
    }
  }

  Future<void> _startScanning() async {
    if (!_cameraService.isInitialized) return;

    // 清除上次扫描的条码缓存，准备扫描新条码
    _lastScannedCode = null;
    _lastScanTime = null;

    await _cameraService.startImageStream((CameraImage image) async {
      if (_isProcessing) return;

      final code = await _barcodeService.scanFromCameraImage(
        image,
        _cameraService.sensorOrientation,
        _cameraService.isFrontCamera,
      );

      // 确保条码非空且有效
      if (code != null && code.trim().isNotEmpty && mounted) {
        final trimmedCode = code.trim();
        final now = DateTime.now();

        // 防止重复识别同一个条码（2秒内不重复处理同一个条码）
        if (_lastScannedCode == trimmedCode &&
            _lastScanTime != null &&
            now.difference(_lastScanTime!).inMilliseconds < 2000) {
          return;
        }

        _lastScannedCode = trimmedCode;
        _lastScanTime = now;
        _handleScannedCode(trimmedCode);
      }
    });
  }

  void _handleScannedCode(String code) {
    if (_isProcessing) return;
    _isProcessing = true;

    setState(() {
      _errorMessage = null;
    });

    if (_state == CheckinState.scanningMember) {
      _handleMemberCode(code);
    } else if (_state == CheckinState.scanningWork) {
      _handleWorkCode(code);
    } else {
      // 如果不在扫描状态，忽略这个条码
      _isProcessing = false;
      return;
    }

    // 注意：_isProcessing 的重置在 _handleMemberCode 和 _handleWorkCode 中处理
    // 成功处理后不需要重置，因为会停止扫描
    // 失败时需要重置，以便继续扫描
  }

  void _handleMemberCode(String code) {
    final provider = context.read<ParticipantProvider>();
    final participant = provider.findByMemberCode(code);

    if (participant == null) {
      setState(() {
        _errorMessage = '未找到选手: $code';
      });
      // 继续扫描，重置处理标志
      _isProcessing = false;
      return;
    }

    // 停止扫描，显示选手信息
    _cameraService.stopImageStream();

    // 清除条码缓存，防止身份码被误识别为作品码
    _lastScannedCode = null;
    _lastScanTime = null;

    setState(() {
      _scannedMemberCode = code;
      _currentParticipant = participant;
      _state = CheckinState.memberScanned;
    });

    // 成功后保持 _isProcessing = true，防止继续处理
  }

  void _handleWorkCode(String code) {
    final provider = context.read<ParticipantProvider>();

    // 检查作品码是否已被使用
    final existingParticipant = provider.findByWorkCode(code);
    if (existingParticipant != null &&
        existingParticipant.id != _currentParticipant?.id) {
      setState(() {
        _errorMessage = '作品码已被使用: ${existingParticipant.name}';
      });
      // 继续扫描，重置处理标志
      _isProcessing = false;
      return;
    }

    // 停止扫描
    _cameraService.stopImageStream();

    setState(() {
      _scannedWorkCode = code;
      _state = CheckinState.completed;
    });

    // 绑定作品码
    _bindWorkCode();

    // 成功后保持 _isProcessing = true，防止继续处理
  }

  Future<void> _bindWorkCode() async {
    if (_scannedMemberCode == null || _scannedWorkCode == null) return;

    try {
      final provider = context.read<ParticipantProvider>();
      await provider.bindWorkCode(_scannedMemberCode!, _scannedWorkCode!);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('检录成功: ${_currentParticipant?.name}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '绑定失败: $e';
          _state = CheckinState.scanningWork;
        });
        _startScanning();
      }
    }
  }

  void _continueToScanWork() {
    // 清除条码缓存，准备扫描新的作品码
    // 重要：将已扫描的身份码设为上次扫描码，防止被再次识别
    _lastScannedCode = _scannedMemberCode;
    _lastScanTime = DateTime.now();
    _isProcessing = false;

    setState(() {
      _state = CheckinState.scanningWork;
      _errorMessage = null;
    });

    // 延迟启动扫描，让相机有时间刷新图像缓存
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _state == CheckinState.scanningWork) {
        _startScanningForWork();
      }
    });
  }

  /// 专门用于扫描作品码的方法，不清除缓存
  Future<void> _startScanningForWork() async {
    if (!_cameraService.isInitialized) return;

    await _cameraService.startImageStream((CameraImage image) async {
      if (_isProcessing) return;

      final code = await _barcodeService.scanFromCameraImage(
        image,
        _cameraService.sensorOrientation,
        _cameraService.isFrontCamera,
      );

      // 确保条码非空且有效
      if (code != null && code.trim().isNotEmpty && mounted) {
        final trimmedCode = code.trim();
        final now = DateTime.now();

        // 防止重复识别同一个条码（2秒内不重复处理同一个条码）
        // 这也会阻止身份码被误识别为作品码
        if (_lastScannedCode == trimmedCode &&
            _lastScanTime != null &&
            now.difference(_lastScanTime!).inMilliseconds < 2000) {
          return;
        }

        _lastScannedCode = trimmedCode;
        _lastScanTime = now;
        _handleScannedCode(trimmedCode);
      }
    });
  }

  void _resetScan() {
    // 重要：将上次扫描的作品码设为缓存，防止被误识别为下一位选手的身份码
    _lastScannedCode = _scannedWorkCode;
    _lastScanTime = DateTime.now();
    _isProcessing = false;

    setState(() {
      _state = CheckinState.scanningMember;
      _scannedMemberCode = null;
      _currentParticipant = null;
      _scannedWorkCode = null;
      _errorMessage = null;
    });

    // 延迟启动扫描，让相机有时间刷新图像缓存
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _state == CheckinState.scanningMember) {
        _startScanningForMember();
      }
    });
  }

  /// 专门用于扫描身份码的方法，不清除缓存
  Future<void> _startScanningForMember() async {
    if (!_cameraService.isInitialized) return;

    await _cameraService.startImageStream((CameraImage image) async {
      if (_isProcessing) return;

      final code = await _barcodeService.scanFromCameraImage(
        image,
        _cameraService.sensorOrientation,
        _cameraService.isFrontCamera,
      );

      // 确保条码非空且有效
      if (code != null && code.trim().isNotEmpty && mounted) {
        final trimmedCode = code.trim();
        final now = DateTime.now();

        // 防止重复识别同一个条码（2秒内不重复处理同一个条码）
        // 这也会阻止上次的作品码被误识别为身份码
        if (_lastScannedCode == trimmedCode &&
            _lastScanTime != null &&
            now.difference(_lastScanTime!).inMilliseconds < 2000) {
          return;
        }

        _lastScannedCode = trimmedCode;
        _lastScanTime = now;
        _handleScannedCode(trimmedCode);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选手检录'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          // 检录统计按钮
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '检录统计',
            onPressed: _showStatistics,
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态提示栏
          _buildStatusBar(),

          // 相机预览区域
          Expanded(flex: 2, child: _buildCameraPreview()),

          // 信息展示区域
          Expanded(flex: 1, child: _buildInfoPanel()),
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (_state) {
      case CheckinState.initial:
        statusText = '正在初始化相机...';
        statusColor = Colors.grey;
        statusIcon = Icons.hourglass_empty;
        break;
      case CheckinState.scanningMember:
        statusText = '请扫描选手身份码';
        statusColor = Colors.blue;
        statusIcon = Icons.qr_code_scanner;
        break;
      case CheckinState.memberScanned:
        statusText = '选手确认';
        statusColor = Colors.orange;
        statusIcon = Icons.person;
        break;
      case CheckinState.scanningWork:
        statusText = '请扫描作品码';
        statusColor = Colors.purple;
        statusIcon = Icons.qr_code;
        break;
      case CheckinState.completed:
        statusText = '检录完成';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: statusColor.withOpacity(0.1),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor),
          const SizedBox(width: 12),
          Text(
            statusText,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    if (_errorMessage != null && _state == CheckinState.initial) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initCamera,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (!_cameraService.isInitialized || _cameraService.controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // 检录完成或选手确认时，不显示相机预览
    if (_state == CheckinState.completed ||
        _state == CheckinState.memberScanned) {
      return _buildParticipantInfo();
    }

    return Stack(
      children: [
        // 相机预览
        ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width:
                    _cameraService.controller!.value.previewSize?.height ?? 0,
                height:
                    _cameraService.controller!.value.previewSize?.width ?? 0,
                child: CameraPreview(_cameraService.controller!),
              ),
            ),
          ),
        ),

        // 扫描框
        Center(
          child: Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.green, width: 3),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),

        // 错误提示
        if (_errorMessage != null)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildParticipantInfo() {
    if (_currentParticipant == null) {
      return const SizedBox.shrink();
    }

    final p = _currentParticipant!;

    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 头像
          CircleAvatar(
            radius: 50,
            backgroundColor: Colors.grey[200],
            child: p.avatarPath != null
                ? ClipOval(
                    child: Image.asset(
                      'assets/images/${p.avatarPath}',
                      fit: BoxFit.cover,
                      width: 100,
                      height: 100,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person,
                        size: 50,
                        color: Colors.grey,
                      ),
                    ),
                  )
                : const Icon(Icons.person, size: 50, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // 姓名
          Text(
            p.name,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // 信息
          Text(
            '参赛编号: ${p.memberCode}',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          if (p.group != null)
            Text(
              '组别: ${p.group}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          if (p.leaderName != null)
            Text(
              '领队: ${p.leaderName}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),

          // 检录状态
          if (_state == CheckinState.completed && _scannedWorkCode != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '作品码: $_scannedWorkCode',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 操作按钮
          if (_state == CheckinState.memberScanned) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _resetScan,
                    icon: const Icon(Icons.cancel),
                    label: const Text('取消'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _continueToScanWork,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('扫描作品码'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (_state == CheckinState.completed) ...[
            ElevatedButton.icon(
              onPressed: _resetScan,
              icon: const Icon(Icons.add),
              label: const Text('继续检录下一位'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 32,
                ),
              ),
            ),
          ],

          const Spacer(),

          // 检录统计
          Consumer<ParticipantProvider>(
            builder: (context, provider, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem(
                    '总人数',
                    provider.totalCount.toString(),
                    Colors.blue,
                  ),
                  _buildStatItem(
                    '已检录',
                    provider.checkedInCount.toString(),
                    Colors.green,
                  ),
                  _buildStatItem(
                    '未检录',
                    provider.uncheckedCount.toString(),
                    Colors.orange,
                  ),
                ],
              );
            },
          ),
        ],
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
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }

  void _showStatistics() {
    final provider = context.read<ParticipantProvider>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('检录统计'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildStatRow('总参赛人数', provider.totalCount),
            _buildStatRow('已检录', provider.checkedInCount),
            _buildStatRow('未检录', provider.uncheckedCount),
            const Divider(),
            _buildStatRow(
              '检录完成率',
              provider.totalCount > 0
                  ? '${(provider.checkedInCount / provider.totalCount * 100).toStringAsFixed(1)}%'
                  : '0%',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
