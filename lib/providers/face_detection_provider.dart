import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kyc_simulation/services/face_detector_service.dart';
import 'dart:typed_data';

class FaceDetectionProvider extends ChangeNotifier {
  late FaceDetectorService _faceDetectorService;
  bool isFrontCamera = true;
  List<String> challengeActions = [
    'smile',
    'blink',
    'lookRight',
    'lookLeft',
    'lookUp',
    'lookDown'
  ];
  int currentActionIndex = 0;
  bool waitingForNeutral = false;

  double? smilingProbability;
  double? leftEyeOpenProbability;
  double? rightEyeOpenProbability;
  double? headEulerAngleY;
  double? headEulerAngleX;
  Rect? faceBoundingBox;
  Size? previewSize;
  String currentAction = 'waiting';
  String status = 'Waiting for face...';

  FaceDetectionProvider() {
    _initializeFaceDetector();
    challengeActions.shuffle();
  }

  void _initializeFaceDetector() {
    _faceDetectorService = FaceDetectorService(
      onFaceDetected: _handleFaceDetected,
      onNoFaceDetected: () {
        faceBoundingBox = null;
        notifyListeners();
      },
    );
  }

  void processImage(CameraImage image) async {
    if (image.format.group != ImageFormatGroup.yuv420) {
      debugPrint('WARNING: CameraImage format is not yuv420!');
      return;
    }

    final inputImage = _getInputImage(image);
    await _faceDetectorService.detectFaces(inputImage);
  }

  void _handleFaceDetected(Face face) {
    smilingProbability = face.smilingProbability;
    leftEyeOpenProbability = face.leftEyeOpenProbability;
    rightEyeOpenProbability = face.rightEyeOpenProbability;
    headEulerAngleY = face.headEulerAngleY;
    headEulerAngleX = face.headEulerAngleX;
    faceBoundingBox = face.boundingBox;

    _updateAction();
    notifyListeners();
  }

  void _updateAction() {
    if (waitingForNeutral) {
      if (_isNeutral()) {
        waitingForNeutral = false;
        status = 'Action completed';
      } else {
        status = 'Please return to neutral position';
      }
      return;
    }

    switch (currentAction) {
      case 'waiting':
        status = 'Waiting for face...';
        break;
      case 'smile':
        if (smilingProbability != null && smilingProbability! > 0.8) {
          status = 'Smile detected!';
          waitingForNeutral = true;
        } else {
          status = 'Please smile';
        }
        break;
      case 'blink':
        if (_isBlinking()) {
          status = 'Blink detected!';
          waitingForNeutral = true;
        } else {
          status = 'Please blink';
        }
        break;
      case 'lookRight':
        if (headEulerAngleY != null && headEulerAngleY! > 20) {
          status = 'Looking right detected!';
          waitingForNeutral = true;
        } else {
          status = 'Please look right';
        }
        break;
      case 'lookLeft':
        if (headEulerAngleY != null && headEulerAngleY! < -20) {
          status = 'Looking left detected!';
          waitingForNeutral = true;
        } else {
          status = 'Please look left';
        }
        break;
      case 'lookUp':
        if (headEulerAngleX != null && headEulerAngleX! < -20) {
          status = 'Looking up detected!';
          waitingForNeutral = true;
        } else {
          status = 'Please look up';
        }
        break;
      case 'lookDown':
        if (headEulerAngleX != null && headEulerAngleX! > 20) {
          status = 'Looking down detected!';
          waitingForNeutral = true;
        } else {
          status = 'Please look down';
        }
        break;
    }
  }

  bool _isNeutral() {
    return smilingProbability != null &&
        smilingProbability! < 0.3 &&
        leftEyeOpenProbability != null &&
        leftEyeOpenProbability! > 0.8 &&
        rightEyeOpenProbability != null &&
        rightEyeOpenProbability! > 0.8 &&
        headEulerAngleY != null &&
        headEulerAngleY!.abs() < 10 &&
        headEulerAngleX != null &&
        headEulerAngleX!.abs() < 10;
  }

  bool _isBlinking() {
    return leftEyeOpenProbability != null &&
        rightEyeOpenProbability != null &&
        leftEyeOpenProbability! < 0.3 &&
        rightEyeOpenProbability! < 0.3;
  }

  void setNextAction(String action) {
    currentAction = action;
    waitingForNeutral = false;
    notifyListeners();
  }

  InputImage _getInputImage(CameraImage image) {
    final nv21 = _convertYUV420ToNV21(image);

    InputImageRotation rotation;
    switch (image.format.raw) {
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

  Uint8List _convertYUV420ToNV21(CameraImage image) {
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

  void dispose() {
    _faceDetectorService.dispose();
    super.dispose();
  }
}
