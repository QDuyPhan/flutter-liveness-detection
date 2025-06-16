import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// Xử lý logic camera
/// Khởi tạo và quản lý CameraController
/// Chuyển đổi định dạng ảnh từ camera
/// Tạo InputImage cho face detection
class CameraService {
  late CameraController cameraController;
  bool isCameraInitialized = false;
  bool isDetecting = false;

  // Callbacks
  final Function(bool) onCameraInitialized;
  final Function(CameraImage) onImageAvailable;

  CameraService({
    required this.onCameraInitialized,
    required this.onImageAvailable,
  });

  Future<bool> isImageFormatSupported(
      CameraDescription camera, ImageFormatGroup formatGroup) async {
    CameraController? testController;
    try {
      testController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: formatGroup,
      );
      await testController.initialize();
      await testController.dispose();
      return true;
    } catch (e) {
      debugPrint('ImageFormatGroup $formatGroup is NOT supported: $e');
      return false;
    }
  }

  Future<void> initializeCamera() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front);

    bool yuv420Supported =
        await isImageFormatSupported(frontCamera, ImageFormatGroup.yuv420);
    ImageFormatGroup formatGroup =
        yuv420Supported ? ImageFormatGroup.yuv420 : ImageFormatGroup.unknown;

    if (!yuv420Supported) {
      debugPrint('Thiết bị không hỗ trợ YUV420, sẽ thử với format mặc định.');
    }

    cameraController = CameraController(
      frontCamera,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: formatGroup,
    );

    await cameraController.initialize();
    isCameraInitialized = true;
    onCameraInitialized(true);
    startImageStream();
  }

  void startImageStream() {
    if (isCameraInitialized) {
      cameraController.startImageStream((CameraImage image) {
        if (!isDetecting) {
          isDetecting = true;
          onImageAvailable(image);
          isDetecting = false;
        }
      });
    }
  }

  Uint8List convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;
    final Uint8List nv21 = Uint8List(ySize + uvSize);

    // Fill Y
    int index = 0;
    for (int i = 0; i < height; i++) {
      nv21.setRange(index, index + width, image.planes[0].bytes,
          i * image.planes[0].bytesPerRow);
      index += width;
    }

    // Fill VU (VU interleaved)
    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;
    int uvIndex = ySize;
    for (int i = 0; i < height ~/ 2; i++) {
      for (int j = 0; j < width ~/ 2; j++) {
        int vIndex = i * uvRowStride + j * uvPixelStride;
        int uIndex = i * uvRowStride + j * uvPixelStride;
        nv21[uvIndex++] = image.planes[2].bytes[vIndex]; // V
        nv21[uvIndex++] = image.planes[1].bytes[uIndex]; // U
      }
    }
    return nv21;
  }

  InputImage getInputImage(CameraImage image) {
    final nv21 = convertYUV420ToNV21(image);

    InputImageRotation rotation;
    switch (cameraController.description.sensorOrientation) {
      case 0:
        rotation = InputImageRotation.rotation0deg;
        break;
      case 90:
        rotation = InputImageRotation.rotation90deg;
        break;
      case 180:
        rotation = InputImageRotation.rotation180deg;
        break;
      case 270:
        rotation = InputImageRotation.rotation270deg;
        break;
      default:
        rotation = InputImageRotation.rotation0deg;
    }

    return InputImage.fromBytes(
      bytes: nv21,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  void dispose() {
    cameraController.dispose();
  }
}
