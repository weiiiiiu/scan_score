import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:permission_handler/permission_handler.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;

  CameraController? get controller => _controller;

  bool get isInitialized => _isInitialized && _controller != null;

  int get sensorOrientation => _controller?.description.sensorOrientation ?? 90;

  Future<bool> initialize() async {
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

      // 3. 选择后置摄像头
      final selectedCamera = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

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
      debugPrint('相机初始化失败: $e');
      _isInitialized = false;
      return false;
    }
  }

  /// 启动图像流
  Future<void> startImageStream(void Function(CameraImage) onImage) async {
    if (_controller == null || !_isInitialized) return;

    if (_controller!.value.isStreamingImages) return;

    try {
      await _controller!.startImageStream(onImage);
    } catch (e) {
      debugPrint('启动流失败: $e');
    }
  }

  // 停止图像流
  Future<void> stopImageStream() async {
    if (_controller == null || !_isInitialized) return;

    if (!_controller!.value.isStreamingImages) return;

    try {
      await _controller!.stopImageStream();
    } catch (e) {
      debugPrint('停止流失败: $e');
    }
  }

  //拍照前必须停止 ImageStream，否则会 Crash 或卡死
  Future<XFile?> takePicture() async {
    if (_controller == null || !_isInitialized) return null;

    try {
      //  如果正在扫码(流开启中)，必须先停止流

      if (_controller!.value.isStreamingImages) {
        await _controller!.stopImageStream();
        // 稍微给一点缓冲时间让相机硬件状态复位
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 2. 拍照
      final file = await _controller!.takePicture();
      return file;
    } catch (e) {
      debugPrint('拍照失败: $e');
      return null;
    }
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
