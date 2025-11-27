import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

/// 条码扫描服务
/// 封装 ML Kit 的条码扫描功能
class BarcodeService {
  final BarcodeScanner _barcodeScanner = BarcodeScanner(
    formats: [
      BarcodeFormat.qrCode,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
    ],
  );

  bool _isProcessing = false;

  /// 从相机图像中扫描条码
  /// 返回扫描到的第一个条码值，如果没有扫描到则返回 null
  Future<String?> scanFromCameraImage(
    CameraImage image,
    int sensorOrientation,
    bool isFrontCamera,
  ) async {
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      final inputImage = _convertCameraImage(
        image,
        sensorOrientation,
        isFrontCamera,
      );
      if (inputImage == null) {
        return null;
      }

      final barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty) {
        final rawValue = barcodes.first.rawValue;
        // 确保条形码内容非null且非空
        if (rawValue != null && rawValue.trim().isNotEmpty) {
          return rawValue.trim();
        }
      }
      return null;
    } catch (e) {
      print('扫描条码失败: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// 将 CameraImage 转换为 InputImage
  InputImage? _convertCameraImage(
    CameraImage image,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    // 获取图像旋转方向
    final rotation = _getImageRotation(sensorOrientation, isFrontCamera);
    if (rotation == null) return null;

    // 获取图像格式
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    // 合并所有平面的字节数据
    final bytes = Uint8List.fromList(
      image.planes.fold<List<int>>(
        [],
        (previousValue, plane) => previousValue..addAll(plane.bytes),
      ),
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: ui.Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  /// 获取图像旋转方向
  InputImageRotation? _getImageRotation(
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    // Android 设备的传感器方向通常是 90 度
    int rotationCompensation = sensorOrientation;

    if (isFrontCamera) {
      rotationCompensation = (sensorOrientation + 360) % 360;
    }

    switch (rotationCompensation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  /// 释放资源
  void dispose() {
    _barcodeScanner.close();
  }
}
