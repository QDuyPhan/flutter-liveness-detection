import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kyc_simulation/controllers/face_detection_controller.dart';

class FaceDetectionView extends StatefulWidget {
  const FaceDetectionView({super.key});

  @override
  _FaceDetectionViewState createState() => _FaceDetectionViewState();
}

class _FaceDetectionViewState extends State<FaceDetectionView> {
  final FaceDetectionController _controller = FaceDetectionController();
  bool _isAllChallengesCompleted = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _controller.challengeActions.shuffle();
  }

  Future<void> _initializeCamera() async {
    await _controller.initializeCamera();
    if (mounted) {
      setState(() {});
      _startFaceDetection();
    }
  }

  void _startFaceDetection() {
    if (_controller.isCameraInitialized) {
      _controller.cameraController.startImageStream((CameraImage image) {
        if (!_controller.isDetecting) {
          _controller.isDetecting = true;
          _controller.detectFaces(image, (face) {
            if (_controller.checkChallenge(face)) {
              setState(() {
                _isAllChallengesCompleted = true;
              });
            }
            _controller.isDetecting = false;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.isCameraInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Face Detection'),
      ),
      body: Stack(
        children: [
          CameraPreview(_controller.cameraController),
          if (_controller.faceBoundingBox != null)
            CustomPaint(
              painter: FaceDetectorPainter(
                _controller.faceBoundingBox!,
                _controller.previewSize ?? Size.zero,
              ),
            ),
          Positioned(
            bottom: 50,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black54,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Current Challenge: ${_controller.challengeActions[_controller.currentActionIndex]}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_isAllChallengesCompleted)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'All challenges completed!',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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

    final Rect scaledRect = Rect.fromLTWH(
      boundingBox.left * size.width / previewSize.width,
      boundingBox.top * size.height / previewSize.height,
      boundingBox.width * size.width / previewSize.width,
      boundingBox.height * size.height / previewSize.height,
    );

    canvas.drawRect(scaledRect, paint);
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.boundingBox != boundingBox;
  }
}
