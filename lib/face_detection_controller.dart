import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kyc_simulation/app_config.dart';

class FaceDetectionController {
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  late CameraController cameraController;
  bool isCameraInitialized = false;
  bool isDetecting = false;
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

  // Callbacks
  final Function(bool) onCameraInitialized;
  final Function(Face) onFaceDetected;
  final Function() onNoFaceDetected;
  final Function(String) onChallengeCompleted;
  final Function(String) onChallengeFailed;

  FaceDetectionController({
    required this.onCameraInitialized,
    required this.onFaceDetected,
    required this.onNoFaceDetected,
    required this.onChallengeCompleted,
    required this.onChallengeFailed,
  }) {
    challengeActions.shuffle();
  }

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
    startFaceDetection();
  }

  void startFaceDetection() {
    if (isCameraInitialized) {
      cameraController.startImageStream((CameraImage image) {
        if (!isDetecting) {
          isDetecting = true;
          detectFaces(image).then((_) {
            isDetecting = false;
          });
        }
      });
    }
  }

  /// chuyển YUV420 thành NV21
  /// Chuyển CameraImage từ YUV420 sang NV21 format (Uint8List)
  /// để dùng với thư viện xử lý ảnh như mlkit, tflite, hoặc native Android.
  /// Cần detect face / send image cho model
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

  Uint8List convertYUV420ToNV21Safe(CameraImage image) {
    final int width = image.width;
    final int height = image.height;

    final int ySize = width * height;
    final int uvSize = width * height ~/ 2;
    final Uint8List nv21 = Uint8List(ySize + uvSize);

    final Uint8List yPlane = image.planes[0].bytes;
    final Uint8List uPlane = image.planes[1].bytes;
    final Uint8List vPlane = image.planes[2].bytes;

    final int yRowStride = image.planes[0].bytesPerRow;

    // Copy Y plane
    int destIndex = 0;
    for (int row = 0; row < height; row++) {
      final int srcIndex = row * yRowStride;
      nv21.setRange(destIndex, destIndex + width, yPlane, srcIndex);
      destIndex += width;
    }

    final int uvRowStride = image.planes[1].bytesPerRow;
    final int uvPixelStride = image.planes[1].bytesPerPixel!;

    // Interleave V and U planes to NV21 format (VU VU VU...)
    int uvStartIndex = ySize;
    for (int row = 0; row < height ~/ 2; row++) {
      for (int col = 0; col < width ~/ 2; col++) {
        final int uvIndex = row * uvRowStride + col * uvPixelStride;
        nv21[uvStartIndex++] = vPlane[uvIndex]; // V
        nv21[uvStartIndex++] = uPlane[uvIndex]; // U
      }
    }

    return nv21;
  }


  Future<void> detectFaces(CameraImage image) async {
    try {
      if (image.format.group != ImageFormatGroup.yuv420) {
        debugPrint('WARNING: CameraImage format is not yuv420!');
        app_config.printLog('e', 'WARNING: CameraImage format is not yuv420!');
        return;
      }

      final nv21 = convertYUV420ToNV21Safe(image);

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

      final inputImage = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      final faces = await faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        app_config.printLog("i", 'Detected ${faces.length} face(s):');
        for (var i = 0; i < faces.length; i++) {
          final face = faces[i];
          app_config.printLog("i", 'Face $i:');
          app_config.printLog("i", '  Bounding box: ${face.boundingBox}');
          app_config.printLog(
            "i",
            '  Head Euler Angle X: ${face.headEulerAngleX}',
          );
          app_config.printLog(
            "i",
            '  Head Euler Angle Y: ${face.headEulerAngleY}',
          );
          app_config.printLog(
            "i",
            '  Head Euler Angle Z: ${face.headEulerAngleZ}',
          );
          if (face.contours.isNotEmpty) {
            app_config.printLog(
              "i",
              '  Contours detected: ${face.contours.keys.length} types',
            );
          }
        }
      } else {
        app_config.printLog("i", 'No faces detected.');
      }

      if (faces.isNotEmpty) {
        final face = faces.first;
        smilingProbability = face.smilingProbability;
        leftEyeOpenProbability = face.leftEyeOpenProbability;
        rightEyeOpenProbability = face.rightEyeOpenProbability;
        headEulerAngleY = face.headEulerAngleY;
        headEulerAngleX = face.headEulerAngleX;
        faceBoundingBox = face.boundingBox;

        onFaceDetected(face);
        checkChallenge(face);
      } else {
        faceBoundingBox = null;
        onNoFaceDetected();
      }
    } catch (e) {
      debugPrint('Error in face detection: $e');
    }
  }

  void checkChallenge(Face face) {
    if (waitingForNeutral) {
      if (isNeutralPosition(face)) {
        debugPrint('Returned to neutral position');
        waitingForNeutral = false;
      } else {
        return;
      }
    }

    String currentAction = challengeActions[currentActionIndex];
    bool actionCompleted = false;

    switch (currentAction) {
      case 'smile':
        actionCompleted =
            face.smilingProbability != null && face.smilingProbability! > 0.5;
        break;
      case 'blink':
        actionCompleted = (face.leftEyeOpenProbability != null &&
                face.leftEyeOpenProbability! < 0.3) ||
            (face.rightEyeOpenProbability != null &&
                face.rightEyeOpenProbability! < 0.3);
        break;
      case 'lookRight':
        actionCompleted =
            face.headEulerAngleY != null && face.headEulerAngleY! > 20;
        break;
      case 'lookLeft':
        actionCompleted =
            face.headEulerAngleY != null && face.headEulerAngleY! < -20;
        break;
      case 'lookUp':
        actionCompleted =
            face.headEulerAngleX != null && face.headEulerAngleX! < -20;
        break;
      case 'lookDown':
        actionCompleted =
            face.headEulerAngleX != null && face.headEulerAngleX! > 20;
        break;
    }

    if (actionCompleted) {
      onChallengeCompleted(currentAction);
      waitingForNeutral = true;
      currentActionIndex++;
      if (currentActionIndex >= challengeActions.length) {
        currentActionIndex = 0;
        challengeActions.shuffle();
      }
    }
  }

  bool isNeutralPosition(Face face) {
    return (face.smilingProbability == null ||
            face.smilingProbability! < 0.3) &&
        (face.headEulerAngleY == null ||
            (face.headEulerAngleY! > -10 && face.headEulerAngleY! < 10)) &&
        (face.headEulerAngleX == null ||
            (face.headEulerAngleX! > -10 && face.headEulerAngleX! < 10));
  }

  void dispose() {
    cameraController.dispose();
    faceDetector.close();
  }
}
