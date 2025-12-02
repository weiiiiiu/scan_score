import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../models/participant.dart';
import '../../providers/participant_provider.dart';
import '../../services/barcode_service.dart';

enum CheckinState {
  initial,
  scanningMember,
  memberScanned,
  scanningWork,
  completed,
}

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  final BarcodeService _barcodeService = BarcodeService();

  CheckinState _state = CheckinState.initial;
  String? _errorMessage;
  bool _isProcessing = false;

  String? _scannedMemberCode;
  Participant? _currentParticipant;
  String? _scannedWorkCode;

  // --- 防抖与节流控制 ---
  String? _lastScannedCode;
  DateTime? _lastScanTime;
  // 强制忽略扫描的时间点（用于切换状态时的冷却）
  DateTime? _ignoreScanUntil;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _barcodeService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  // UI 暂停时不处理数据
  bool get _isScanPaused {
    return _state == CheckinState.memberScanned ||
        _state == CheckinState.completed ||
        _state == CheckinState.initial;
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _errorMessage = '未检测到相机设备');
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _state = CheckinState.scanningMember;
        });
        _startImageStream();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = '相机初始化失败: $e');
    }
  }

  void _startImageStream() {
    if (_controller == null) return;

    _controller!.startImageStream((CameraImage image) async {
      // 1. 基础状态检查
      if (_isScanPaused || _isProcessing) return;

      // 2. [冷却机制]：检查是否处于“冷却期”
      // 如果当前时间还在忽略时间内，直接丢弃这一帧，不进行识别
      if (_ignoreScanUntil != null &&
          DateTime.now().isBefore(_ignoreScanUntil!)) {
        return;
      }

      _isProcessing = true;
      try {
        final code = await _barcodeService.scanFromCameraImage(
          image,
          _controller!.description.sensorOrientation,
          _controller!.description.lensDirection == CameraLensDirection.front,
        );

        if (code != null && code.trim().isNotEmpty && mounted) {
          _routeScannedCode(code.trim());
        }
      } catch (e) {
        debugPrint('Stream process error: $e');
      } finally {
        _isProcessing = false;
      }
    });
  }

  // 验证选手码格式：88开头，总共8位数字
  bool _isValidMemberCode(String code) {
    return code.length == 8 &&
        code.startsWith('88') &&
        RegExp(r'^\d{8}$').hasMatch(code);
  }

  // 验证作品码格式：99开头，总共8位数字
  bool _isValidWorkCode(String code) {
    return code.length == 8 &&
        code.startsWith('99') &&
        RegExp(r'^\d{8}$').hasMatch(code);
  }

  void _routeScannedCode(String code) {
    final now = DateTime.now();

    // 3. 全局防抖逻辑
    // 如果码和上次一样，且时间间隔小于 1.5秒，直接忽略
    if (_lastScannedCode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 1500) {
      return;
    }

    // 根据当前状态验证条码格式
    if (_state == CheckinState.scanningMember) {
      // 扫描选手码时，必须是88开头的8位数字
      if (!_isValidMemberCode(code)) {
        // 格式不对，静默忽略，继续扫描
        debugPrint('忽略无效选手码: $code (需要88开头的8位数字)');
        return;
      }
    } else if (_state == CheckinState.scanningWork) {
      // 扫描作品码时，必须是99开头的8位数字
      if (!_isValidWorkCode(code)) {
        // 格式不对，静默忽略，继续扫描
        debugPrint('忽略无效作品码: $code (需要99开头的8位数字)');
        return;
      }
    }

    // 更新记录
    _lastScannedCode = code;
    _lastScanTime = now;

    if (_state == CheckinState.scanningMember) {
      _handleMemberCode(code);
    } else if (_state == CheckinState.scanningWork) {
      _handleWorkCode(code);
    }
  }

  void _handleMemberCode(String code) {
    final provider = context.read<ParticipantProvider>();
    final participant = provider.findByMemberCode(code);

    if (participant == null) {
      if (_errorMessage != '未找到选手: $code') {
        setState(() => _errorMessage = '未找到选手: $code');
      }
      return;
    }

    // 检查是否已检录
    if (participant.checkStatus == 1) {
      setState(() {
        _errorMessage = '该选手已检录: ${participant.memberCode}';
      });
      return;
    }

    setState(() {
      _scannedMemberCode = code;
      _currentParticipant = participant;
      _state = CheckinState.memberScanned;
      _errorMessage = null;
    });
  }

  void _handleWorkCode(String code) {
    // 【修改点】：已移除 "code == _scannedMemberCode" 的拦截判断
    // 允许作品码与身份码一致。

    final provider = context.read<ParticipantProvider>();
    final existingParticipant = provider.findByWorkCode(code);

    // 检查作品码是否已被【其他人】使用
    // 如果 existingParticipant.id == _currentParticipant.id，说明是自己重复扫或者同一个码，允许通过
    if (existingParticipant != null &&
        existingParticipant.id != _currentParticipant?.id) {
      setState(() => _errorMessage = '作品码已被使用: ${existingParticipant.name}');
      return;
    }

    setState(() {
      _scannedWorkCode = code;
      _state = CheckinState.completed;
      _errorMessage = null;
    });

    _bindWorkCode();
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
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '绑定失败: $e';
          _state = CheckinState.scanningWork;
          // 绑定失败重试时，也给一点冷却时间
          _ignoreScanUntil = DateTime.now().add(
            const Duration(milliseconds: 1000),
          );
        });
      }
    }
  }

  // --- 状态切换控制 ---

  // 点击“扫描作品码”按钮
  void _continueToScanWork() {
    setState(() {
      _state = CheckinState.scanningWork;
      _errorMessage = null;

      // 1. 设置“冷却期”：未来 800毫秒内，不管扫到什么都忽略
      // 防止手没移开导致瞬间误触
      _ignoreScanUntil = DateTime.now().add(const Duration(milliseconds: 800));

      // 2. 重置防抖计时器为“现在”
      // 这里的逻辑很关键：我们把上次扫描的码设为当前身份码。
      // 如果 0.8秒后摄像头还对着同一个码，防抖逻辑(diff < 1.5s)会阻止它被识别。
      // 只有移开再回来，或者等待 1.5秒后，才能再次识别同一个码（作为作品码）。
      _lastScannedCode = _scannedMemberCode;
      _lastScanTime = DateTime.now();
    });
  }

  // 点击“继续检录下一位”或“取消”按钮
  void _resetScan() {
    setState(() {
      _state = CheckinState.scanningMember;
      _scannedMemberCode = null;
      _currentParticipant = null;
      _scannedWorkCode = null;
      _errorMessage = null;

      _lastScannedCode = null;

      // 同样给予一点冷却时间
      _ignoreScanUntil = DateTime.now().add(const Duration(milliseconds: 800));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选手检录'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          Expanded(flex: 2, child: _buildCameraArea()),
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
        statusIcon = Icons.image;
        break;
      case CheckinState.completed:
        statusText = '检录完成';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: statusColor.withValues(alpha: 0.1),
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

  Widget _buildCameraArea() {
    return Stack(
      fit: StackFit.expand,
      children: [
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
          const Center(child: CircularProgressIndicator()),

        if (!_isScanPaused)
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.greenAccent, width: 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.add, color: Colors.greenAccent, size: 30),
              ),
            ),
          ),

        if (_errorMessage != null)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),

        if (_state == CheckinState.memberScanned ||
            _state == CheckinState.completed)
          Container(
            color: Colors.white.withValues(alpha: 0.95),
            child: _buildParticipantInfo(),
          ),
      ],
    );
  }

  Widget _buildParticipantInfo() {
    if (_currentParticipant == null) return const SizedBox.shrink();
    final p = _currentParticipant!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[200],
              child: const Icon(Icons.person, size: 50, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Text(
              p.name,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '参赛编号: ${p.memberCode}',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            if (p.group != null)
              Text(
                '组别: ${p.group}',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            if (_state == CheckinState.completed &&
                _scannedWorkCode != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border.all(color: Colors.green),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      '作品码: $_scannedWorkCode',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(child: Center(child: _buildActionButtons())),
          const Divider(),
          Consumer<ParticipantProvider>(
            builder: (context, provider, _) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildStatItem('总人数', '${provider.totalCount}', Colors.blue),
                  _buildStatItem(
                    '已检录',
                    '${provider.checkedInCount}',
                    Colors.green,
                  ),
                  _buildStatItem(
                    '未检录',
                    '${provider.uncheckedCount}',
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

  Widget _buildActionButtons() {
    if (_state == CheckinState.memberScanned) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _resetScan,
              icon: const Icon(Icons.cancel),
              label: const Text('取消'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
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
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      );
    } else if (_state == CheckinState.completed) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _resetScan,
          icon: const Icon(Icons.person_add),
          label: const Text('继续检录下一位'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    } else {
      return Text(
        _state == CheckinState.scanningMember ? '请对准选手身份码' : '请对准作品码',
        style: TextStyle(color: Colors.grey[600], fontSize: 16),
      );
    }
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
