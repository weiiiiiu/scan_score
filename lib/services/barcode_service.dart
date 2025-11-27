import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/foundation.dart';
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
      // 1. 在 Isolate 中处理图像数据转换 (CPU 密集型)
      final imageData = await Isolate.run(
        () => _convertImageInIsolate(
          image.planes.map((p) => p.bytes).toList(),
          image.width,
          image.height,
          image.format.raw,
          image.planes[0].bytesPerRow,
          sensorOrientation,
          isFrontCamera,
        ),
      );

      if (imageData == null) return null;

      // 2. 创建 InputImage (必须在主线程)
      final inputImage = InputImage.fromBytes(
        bytes: imageData.bytes,
        metadata: InputImageMetadata(
          size: Size(imageData.width, imageData.height),
          rotation: imageData.rotation,
          format: imageData.format,
          bytesPerRow: imageData.bytesPerRow,
        ),
      );

      // 3. ML Kit 处理 (内部已优化)
      final barcodes = await _barcodeScanner.processImage(inputImage);

      // 4. 返回第一个有效条码
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

  /// 在 Isolate 中转换图像数据
  static _ImageData? _convertImageInIsolate(
    List<Uint8List> planes,
    int width,
    int height,
    int formatRaw,
    int bytesPerRow,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    // 1. 获取图片格式
    final format = InputImageFormatValue.fromRawValue(formatRaw);
    if (format == null) return null;

    // 2. 拼接所有平面的字节
    final allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    // 3. 处理旋转角度
    final rotation = _getImageRotation(sensorOrientation, isFrontCamera);
    if (rotation == null) return null;

    return _ImageData(
      bytes: bytes,
      width: width.toDouble(),
      height: height.toDouble(),
      rotation: rotation,
      format: format,
      bytesPerRow: bytesPerRow,
    );
  }

  /// 获取图像旋转方向
  static InputImageRotation? _getImageRotation(
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    var rotation = sensorOrientation;

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

    return InputImageRotationValue.fromRawValue(rotation);
  }
}

/// 用于在 Isolate 间传递图像数据
class _ImageData {
  final Uint8List bytes;
  final double width;
  final double height;
  final InputImageRotation rotation;
  final InputImageFormat format;
  final int bytesPerRow;

  _ImageData({
    required this.bytes,
    required this.width,
    required this.height,
    required this.rotation,
    required this.format,
    required this.bytesPerRow,
  });
}
