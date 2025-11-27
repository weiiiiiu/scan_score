import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // 需要引用这个以使用 WriteBuffer
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeService {
  // 指定需要识别的条码格式，提高识别速度
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

  /// 从相机流图片中识别条码
  Future<String?> scanFromCameraImage(
    CameraImage image,
    int sensorOrientation,
    bool isFrontCamera,
  ) async {
    // 防止并发处理
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
      // 1. 将 CameraImage 转换为 ML Kit 需要的 InputImage
      final inputImage = _inputImageFromCameraImage(
        image,
        sensorOrientation,
        isFrontCamera,
      );
      if (inputImage == null) return null;

      // 2. 处理图片
      final barcodes = await _barcodeScanner.processImage(inputImage);

      // 3. 返回第一个有效条码
      for (final barcode in barcodes) {
        if (barcode.rawValue != null && barcode.rawValue!.trim().isNotEmpty) {
          return barcode.rawValue!.trim();
        }
      }
    } catch (e) {
      debugPrint('Error detecting barcode: $e');
    } finally {
      _isProcessing = false;
    }
    return null;
  }

  void dispose() {
    _barcodeScanner.close();
  }

  /// 核心转换逻辑：CameraImage -> InputImage
  /// 优化点：使用 WriteBuffer 替代 fold，大幅提升性能
  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    // 1. 获取图片格式
    final format = InputImageFormatValue.fromRawValue(image.format.raw);

    // 校验格式支持 (Android: nv21, iOS: bgra8888)
    // 如果格式不支持，直接返回 null，避免 Crash
    if (format == null) return null;

    // 2. 拼接所有平面的字节 (性能优化部分)
    // 使用 WriteBuffer 避免创建大量临时对象
    final allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    // 3. 获取图片尺寸
    final size = Size(image.width.toDouble(), image.height.toDouble());

    // 4. 处理旋转角度
    final imageRotation = _getImageRotation(sensorOrientation, isFrontCamera);
    if (imageRotation == null) return null;

    final inputImageMetadata = InputImageMetadata(
      size: size,
      rotation: imageRotation,
      format: format,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }

  /// 获取图像旋转方向
  InputImageRotation? _getImageRotation(
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    var rotation = sensorOrientation;

    // Android 设备通常是 90度，iOS 通常是 90度
    // 此处逻辑主要由 CameraController 的 sensorOrientation 决定
    if (Platform.isIOS) {
      rotation = sensorOrientation;
    } else if (Platform.isAndroid) {
      var rotationCompensation = sensorOrientation;
      if (isFrontCamera) {
        rotationCompensation = (sensorOrientation + 360) % 360;
      } else {
        rotationCompensation = sensorOrientation;
      }
      rotation = rotationCompensation;
    }

    // 将角度转换为 ML Kit 枚举
    return InputImageRotationValue.fromRawValue(rotation);
  }
}
