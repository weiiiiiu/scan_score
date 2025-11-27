import 'dart:async';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

/// 相机服务 (Android 专用优化版)
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  /// 获取相机控制器
  CameraController? get controller => _controller;

  /// 是否已初始化
  bool get isInitialized => _isInitialized && _controller != null;

  /// 获取相机传感器方向
  int get sensorOrientation => _controller?.description.sensorOrientation ?? 90;

  /// 是否是前置摄像头
  bool get isFrontCamera =>
      _controller?.description.lensDirection == CameraLensDirection.front;

  /// 初始化相机
  Future<bool> initialize({bool preferBackCamera = true}) async {
    try {
      // 1. 请求权限
      if (!await Permission.camera.request().isGranted) {
        return false;
      }

      // 2. 获取相机
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        return false;
      }

      // 3. 选择前后置
      final cameraDirection = preferBackCamera
          ? CameraLensDirection.back
          : CameraLensDirection.front;

      final selectedCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == cameraDirection,
        orElse: () => _cameras!.first,
      );

      // 4. 创建控制器
      // Android 核心优化：强制使用 nv21，这是 ML Kit 在 Android 上必须的格式
      // 分辨率设为 high，兼顾扫码精度和拍照清晰度
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      // 5. 初始化
      await _controller!.initialize();
      _isInitialized = true;

      return true;
    } catch (e) {
      print('相机初始化失败: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// 开始图像流 (扫码用)
  Future<void> startImageStream(void Function(CameraImage) onImage) async {
    if (_controller == null || !_isInitialized) return;

    // 防止重复启动导致 Crash
    if (_controller!.value.isStreamingImages) return;

    try {
      await _controller!.startImageStream(onImage);
    } catch (e) {
      print('启动流失败: $e');
    }
  }

  /// 停止图像流
  Future<void> stopImageStream() async {
    if (_controller == null || !_isInitialized) return;

    // 关键修复：只有在流运行中才停止，否则 Android 会抛出 CameraException
    if (!_controller!.value.isStreamingImages) return;

    try {
      await _controller!.stopImageStream();
    } catch (e) {
      print('停止流失败: $e');
    }
  }

  /// 拍照
  /// Android 关键修复：拍照前必须停止 ImageStream，否则会 Crash 或卡死
  Future<XFile?> takePicture() async {
    if (_controller == null || !_isInitialized) return null;

    try {
      // 1. 如果正在扫码(流开启中)，必须先停止流
      // 注意：这会导致画面瞬间卡顿一下，这是 Android 硬件限制正常的
      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
        // 稍微给一点缓冲时间让相机硬件状态复位
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 2. 拍照
      final file = await _controller!.takePicture();
      return file;
    } catch (e) {
      print('拍照失败: $e');
      return null;
    }
  }

  /// 切换前后置
  Future<bool> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return false;

    // 获取当前反向的镜头方向
    final newDirection = isFrontCamera
        ? CameraLensDirection.back
        : CameraLensDirection.front;

    // 释放旧控制器
    await dispose();

    // 重新初始化
    return initialize(
      preferBackCamera: newDirection == CameraLensDirection.back,
    );
  }

  /// 释放资源
  Future<void> dispose() async {
    _isInitialized = false;
    // 释放前先确保流停止
    if (_controller != null && _controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
    await _controller?.dispose();
    _controller = null;
  }
}
