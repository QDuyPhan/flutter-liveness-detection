import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kyc_simulation/app_config.dart';
import 'package:kyc_simulation/face_detection_controller.dart';

class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  _FaceDetectionPageState createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  late FaceDetectionController _controller;
  bool isCameraInitialized = false;
  double? smilingProbability;
  double? leftEyeOpenProbability;
  double? rightEyeOpenProbability;
  double? headEulerAngleY;
  double? headEulerAngleX;
  Rect? faceBoundingBox;
  Size? previewSize;
  String currentAction = '';
  bool waitingForNeutral = false;

  @override
  void initState() {
    super.initState();
    _controller = FaceDetectionController(
      onCameraInitialized: (initialized) {
        setState(() {
          isCameraInitialized = initialized;
        });
      },
      onFaceDetected: (face) {
        setState(() {
          smilingProbability = face.smilingProbability;
          leftEyeOpenProbability = face.leftEyeOpenProbability;
          rightEyeOpenProbability = face.rightEyeOpenProbability;
          headEulerAngleY = face.headEulerAngleY;
          headEulerAngleX = face.headEulerAngleX;
          faceBoundingBox = face.boundingBox;
        });
      },
      onNoFaceDetected: () {
        setState(() {
          faceBoundingBox = null;
        });
      },
      onChallengeCompleted: (action) {
        setState(() {
          currentAction = action;
          waitingForNeutral = true;
        });
      },
      onChallengeFailed: (action) {
        setState(() {
          currentAction = action;
        });
      },
    );
    _controller.initializeCamera();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isCameraInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Detection'),
      ),
      body: Stack(
        children: [
          CameraPreview(_controller.cameraController),
          if (faceBoundingBox != null)
            CustomPaint(
              painter: FaceDetectorPainter(
                faceBoundingBox!,
                _controller.cameraController.value.previewSize!,
              ),
            ),
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Current Action: ${_getActionText(currentAction)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (waitingForNeutral)
                    const Text(
                      'Please return to neutral position',
                      style: TextStyle(
                        color: Colors.yellow,
                        fontSize: 16,
                      ),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'Smile: ${_formatProbability(smilingProbability)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Left Eye: ${_formatProbability(leftEyeOpenProbability)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Right Eye: ${_formatProbability(rightEyeOpenProbability)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Head Angle Y: ${_formatAngle(headEulerAngleY)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Head Angle X: ${_formatAngle(headEulerAngleX)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getActionText(String action) {
    switch (action) {
      case 'smile':
        return 'Smile';
      case 'blink':
        return 'Blink';
      case 'lookRight':
        return 'Look Right';
      case 'lookLeft':
        return 'Look Left';
      case 'lookUp':
        return 'Look Up';
      case 'lookDown':
        return 'Look Down';
      default:
        return 'Waiting...';
    }
  }

  String _formatProbability(double? probability) {
    if (probability == null) return 'N/A';
    return '${(probability * 100).toStringAsFixed(1)}%';
  }

  String _formatAngle(double? angle) {
    if (angle == null) return 'N/A';
    return '${angle.toStringAsFixed(1)}°';
  }
}

class FaceDetectorPainter extends CustomPainter {
  final Rect boundingBox;
  final Size previewSize;

  FaceDetectorPainter(this.boundingBox, this.previewSize);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.green;

    final double scaleX = size.width / previewSize.width;
    final double scaleY = size.height / previewSize.height;

    final Rect scaledRect = Rect.fromLTRB(
      boundingBox.left * scaleX,
      boundingBox.top * scaleY,
      boundingBox.right * scaleX,
      boundingBox.bottom * scaleY,
    );

    canvas.drawRect(scaledRect, paint);
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox;
  }
}
