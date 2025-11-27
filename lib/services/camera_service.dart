import 'dart:ui' show Offset;
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

/// 相机服务
/// 封装相机控制，支持实时预览、扫码和拍照
class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  /// 获取相机控制器
  CameraController? get controller => _controller;

  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 获取相机传感器方向
  int get sensorOrientation => _controller?.description.sensorOrientation ?? 0;

  /// 是否是前置摄像头
  bool get isFrontCamera =>
      _controller?.description.lensDirection == CameraLensDirection.front;

  /// 初始化相机
  /// [preferBackCamera] 优先使用后置摄像头
  Future<bool> initialize({bool preferBackCamera = true}) async {
    try {
      // 请求相机权限
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        print('相机权限未授予');
        return false;
      }

      // 获取可用相机列表
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        print('没有可用的相机');
        return false;
      }

      // 选择相机
      CameraDescription selectedCamera;
      if (preferBackCamera) {
        selectedCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => _cameras!.first,
        );
      } else {
        selectedCamera = _cameras!.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.front,
          orElse: () => _cameras!.first,
        );
      }

      // 创建控制器
      _controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      // 初始化控制器
      await _controller!.initialize();
      _isInitialized = true;

      return true;
    } catch (e) {
      print('初始化相机失败: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// 开始图像流（用于实时扫码）
  Future<void> startImageStream(void Function(CameraImage) onImage) async {
    if (_controller == null || !_isInitialized) {
      throw Exception('相机未初始化');
    }

    await _controller!.startImageStream(onImage);
  }

  /// 停止图像流
  Future<void> stopImageStream() async {
    if (_controller == null || !_isInitialized) return;

    try {
      await _controller!.stopImageStream();
    } catch (e) {
      print('停止图像流失败: $e');
    }
  }

  /// 拍照
  Future<XFile?> takePicture() async {
    if (_controller == null || !_isInitialized) {
      throw Exception('相机未初始化');
    }

    try {
      final file = await _controller!.takePicture();
      return file;
    } catch (e) {
      print('拍照失败: $e');
      return null;
    }
  }

  /// 切换相机
  Future<bool> switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) {
      return false;
    }

    try {
      final currentDirection = _controller?.description.lensDirection;
      final newDirection = currentDirection == CameraLensDirection.back
          ? CameraLensDirection.front
          : CameraLensDirection.back;

      final newCamera = _cameras!.firstWhere(
        (camera) => camera.lensDirection == newDirection,
        orElse: () => _cameras!.first,
      );

      await dispose();

      _controller = CameraController(
        newCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.nv21,
      );

      await _controller!.initialize();
      _isInitialized = true;

      return true;
    } catch (e) {
      print('切换相机失败: $e');
      return false;
    }
  }

  /// 设置闪光灯模式
  Future<void> setFlashMode(FlashMode mode) async {
    if (_controller == null || !_isInitialized) return;

    try {
      await _controller!.setFlashMode(mode);
    } catch (e) {
      print('设置闪光灯失败: $e');
    }
  }

  /// 设置对焦点
  Future<void> setFocusPoint(double x, double y) async {
    if (_controller == null || !_isInitialized) return;

    try {
      await _controller!.setFocusPoint(Offset(x, y));
    } catch (e) {
      print('设置对焦点失败: $e');
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    _isInitialized = false;
    await _controller?.dispose();
    _controller = null;
  }
}
