import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kyc_simulation/app_config.dart';

///Xử lý logic nhận diện khuôn mặt
/// Khởi tạo và quản lý FaceDetector
/// Xử lý kết quả nhận diện khuôn mặt
class FaceDetectorService {
  final FaceDetector faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  // Callbacks
  final Function(Face) onFaceDetected;
  final Function() onNoFaceDetected;

  FaceDetectorService({
    required this.onFaceDetected,
    required this.onNoFaceDetected,
  });

  Future<void> detectFaces(InputImage inputImage) async {
    try {
      final faces = await faceDetector.processImage(inputImage);
      debugPrint('Number of faces detected: ${faces.length}');
      app_config.printLog('i', 'Number of faces detected: ${faces.length}');

      if (faces.isNotEmpty) {
        final face = faces.first;
        onFaceDetected(face);
      } else {
        onNoFaceDetected();
      }
    } catch (e) {
      debugPrint('Error in face detection: $e');
    }
  }

  void dispose() {
    faceDetector.close();
  }
}
