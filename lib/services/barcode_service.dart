import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class BarcodeService {
  /// ML Kit 条码扫描器实例
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
    if (_isProcessing) return null;
    _isProcessing = true;

    try {
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
      final inputImage = InputImage.fromBytes(
        bytes: imageData.bytes,
        metadata: InputImageMetadata(
          size: Size(imageData.width, imageData.height),
          rotation: imageData.rotation,
          format: imageData.format,
          bytesPerRow: imageData.bytesPerRow,
        ),
      );
      final barcodes = await _barcodeScanner.processImage(inputImage);
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

  static _ImageData? _convertImageInIsolate(
    List<Uint8List> planes,
    int width,
    int height,
    int formatRaw,
    int bytesPerRow,
    int sensorOrientation,
    bool isFrontCamera,
  ) {
    final format = InputImageFormatValue.fromRawValue(formatRaw);
    if (format == null) return null;
    final allBytes = WriteBuffer();
    for (final plane in planes) {
      allBytes.putUint8List(plane);
    }
    final bytes = allBytes.done().buffer.asUint8List();

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
