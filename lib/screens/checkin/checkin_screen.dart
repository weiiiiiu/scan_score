import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import '../../models/participant.dart';
import '../../providers/participant_provider.dart';
import '../../services/barcode_service.dart';
// 注意：移除了 CameraService 引用，直接使用原生 Controller 以获得更好的流控制

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

class _CheckinScreenState extends State<CheckinScreen>
    with WidgetsBindingObserver {
  // 核心控制器与服务
  CameraController? _controller;
  final BarcodeService _barcodeService = BarcodeService();

  // 状态管理
  CheckinState _state = CheckinState.initial;
  String? _errorMessage;

  // 扫描控制锁
  bool _isProcessing = false; // 是否正在处理上一帧（并发锁）

  // 数据缓存
  String? _scannedMemberCode;
  Participant? _currentParticipant;
  String? _scannedWorkCode;

  // 防抖控制
  String? _lastScannedCode;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    // 监听应用生命周期（处理切后台相机资源释放）
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
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      // 应用进入后台，释放相机
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      // 应用回到前台，重新初始化
      _initCamera();
    }
  }

  /// 计算当前是否应该暂停扫描逻辑（流在跑，但我们忽略数据）
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

      // 优先使用后置相机
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        camera,
        ResolutionPreset.medium, // 建议 Medium 或 High，太高会导致帧率下降且识别慢
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
        // 初始化完成后立即启动流，且不再停止
        _startImageStream();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = '相机初始化失败: $e');
      }
    }
  }

  void _startImageStream() {
    if (_controller == null) return;

    _controller!.startImageStream((CameraImage image) async {
      // 1. 如果当前状态不需要扫描，或上一帧还在处理，直接丢弃
      if (_isScanPaused || _isProcessing) return;

      _isProcessing = true;
      try {
        // 2. 调用 BarcodeService 识别
        final code = await _barcodeService.scanFromCameraImage(
          image,
          _controller!.description.sensorOrientation,
          _controller!.description.lensDirection == CameraLensDirection.front,
        );

        // 3. 如果识别到有效条码，进行处理
        if (code != null && code.trim().isNotEmpty && mounted) {
          _routeScannedCode(code.trim());
        }
      } catch (e) {
        debugPrint('Stream process error: $e');
      } finally {
        // 4. 释放锁
        _isProcessing = false;
      }
    });
  }

  /// 路由分发：根据当前状态处理扫描到的码
  void _routeScannedCode(String code) {
    // 全局防抖：防止同一秒内重复触发相同的码
    final now = DateTime.now();
    if (_lastScannedCode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 1500) {
      return;
    }
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
      setState(() {
        _errorMessage = '未找到选手: $code';
      });
      return;
    }

    // 成功找到选手
    // 状态变更为 memberScanned 后，_isScanPaused 会自动变 true，停止处理流数据
    setState(() {
      _scannedMemberCode = code;
      _currentParticipant = participant;
      _state = CheckinState.memberScanned;
      _errorMessage = null;
    });
  }

  void _handleWorkCode(String code) {
    // 1. 核心修复：防止扫描到刚才的身份码
    if (code == _scannedMemberCode) {
      setState(() {
        _errorMessage = '请勿重复扫描身份码，请扫描作品码';
      });
      return;
    }

    // 2. 检查作品码逻辑
    final provider = context.read<ParticipantProvider>();
    final existingParticipant = provider.findByWorkCode(code);

    // 如果作品码已被其他人使用
    if (existingParticipant != null &&
        existingParticipant.id != _currentParticipant?.id) {
      setState(() {
        _errorMessage = '作品码已被使用: ${existingParticipant.name}';
      });
      return;
    }

    // 3. 扫描成功，进入完成状态
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
          // 如果失败，回退状态允许重新扫描作品码
          _state = CheckinState.scanningWork;
        });
      }
    }
  }

  // 点击“扫描作品码”按钮
  void _continueToScanWork() {
    setState(() {
      _state = CheckinState.scanningWork;
      _errorMessage = null;
      // 注意：这里不需要清空 _lastScannedCode
      // 这样如果用户还没移开摄像头，防抖逻辑会阻止它立刻识别当前的身份码
      // 同时 handleWorkCode 里的 if check 也会双重保障
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
      _lastScannedCode = null; // 清空缓存，准备迎接新选手
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选手检录'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: '检录统计',
            onPressed: _showStatistics,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildStatusBar(),
          // 预览区域占比较大
          Expanded(flex: 2, child: _buildCameraArea()),
          // 底部操作面板
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

  /// 构建相机与覆盖层的 Stack
  Widget _buildCameraArea() {
    // 即使在 memberScanned 状态，也保持相机预览在底层
    // 这样切换状态时不会有黑屏
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 相机预览层
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

        // 2. 扫描框 (仅在扫描状态显示)
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

        // 3. 错误提示层 (Toast 样式)
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

        // 4. 信息详情覆盖层 (当确认信息或完成时，覆盖在相机之上)
        if (_state == CheckinState.memberScanned ||
            _state == CheckinState.completed)
          Container(
            color: Colors.white.withOpacity(0.95), // 不透明背景遮挡相机
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

            // 如果已完成，显示绑定的作品码
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
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        children: [
          // 操作按钮区域
          Expanded(child: Center(child: _buildActionButtons())),

          const Divider(),

          // 统计数据
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
      // 扫描中状态
      return Text(
        _state == CheckinState.scanningMember ? '请对准选手身份码' : '请对准作品码',
        style: TextStyle(color: Colors.grey[600], fontSize: 16),
      );
    }
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
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
