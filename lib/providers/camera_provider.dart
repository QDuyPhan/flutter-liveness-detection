import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kyc_simulation/services/camera_service.dart';
import 'package:kyc_simulation/providers/face_detection_provider.dart';

class CameraProvider extends ChangeNotifier {
  late CameraService _cameraService;
  bool isCameraInitialized = false;
  bool isDetecting = false;
  FaceDetectionProvider? _faceDetectionProvider;

  CameraProvider() {
    _initializeCamera();
  }

  void setFaceDetectionProvider(FaceDetectionProvider provider) {
    _faceDetectionProvider = provider;
  }

  void _initializeCamera() {
    _cameraService = CameraService(
      onCameraInitialized: (initialized) {
        isCameraInitialized = initialized;
        notifyListeners();
      },
      onImageAvailable: (image) {
        _faceDetectionProvider?.processImage(image);
      },
    );
  }

  CameraController get cameraController => _cameraService.cameraController;

  void dispose() {
    _cameraService.dispose();
    super.dispose();
  }
}
