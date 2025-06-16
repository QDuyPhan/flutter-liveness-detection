import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:kyc_simulation/app_config.dart';
import 'package:kyc_simulation/face_detection_controller.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/foundation.dart';

class FaceDetectionPage extends StatefulWidget {
  const FaceDetectionPage({super.key});

  @override
  _FaceDetectionPageState createState() => _FaceDetectionPageState();
}

class _FaceDetectionPageState extends State<FaceDetectionPage> {
  late APIFace _apiFace;
  bool isCameraInitialized = false;
  Face? _mainFace;
  Rect? faceBoundingBox;
  Size? previewSize;
  StreamSubscription? _faceStreamSub;

  @override
  void initState() {
    super.initState();
    _apiFace = APIFace();
    _apiFace.init(RootIsolateToken.instance!);
    _apiFace.start().then((_) {
      setState(() {
        isCameraInitialized = true;
      });
    });
    _faceStreamSub =
        _apiFace.camera.streamDectectFaceController.stream.listen((event) {
      if (event is List && event[0] is List<Face> && event[1] != null) {
        final List<Face> faces = event[0];
        if (faces.isNotEmpty) {
          // Lấy khuôn mặt lớn nhất (theo width)
          Face mainFace = faces.reduce(
              (a, b) => a.boundingBox.width > b.boundingBox.width ? a : b);
          setState(() {
            _mainFace = mainFace;
            faceBoundingBox = mainFace.boundingBox;
            // previewSize sẽ lấy từ cameraController
            if (_apiFace.camera.controller != null &&
                _apiFace.camera.controller!.value.isInitialized) {
              previewSize = _apiFace.camera.controller!.value.previewSize;
            }
          });
        } else {
          setState(() {
            _mainFace = null;
            faceBoundingBox = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _faceStreamSub?.cancel();
    _apiFace.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isCameraInitialized ||
        _apiFace.camera.controller == null ||
        !_apiFace.camera.controller!.value.isInitialized) {
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
          CameraPreview(_apiFace.camera.controller!),
          if (faceBoundingBox != null && previewSize != null)
            CustomPaint(
              painter: FaceDetectorPainter(
                faceBoundingBox!,
                previewSize!,
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
                    'Smile: ${_formatProbability(_mainFace?.smilingProbability)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Left Eye: ${_formatProbability(_mainFace?.leftEyeOpenProbability)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Right Eye: ${_formatProbability(_mainFace?.rightEyeOpenProbability)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Head Angle Y: ${_formatAngle(_mainFace?.headEulerAngleY)}',
                    style: const TextStyle(color: Colors.white),
                  ),
                  Text(
                    'Head Angle X: ${_formatAngle(_mainFace?.headEulerAngleX)}',
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
