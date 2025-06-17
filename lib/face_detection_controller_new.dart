import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as imglib;

import 'app_config.dart';

@pragma('vm:entry-point')
Future<void> processImage(List<Object> args) async {
  try {
    SendPort sendPort = args[0] as SendPort;
    RootIsolateToken rootIsolateToken = args[1] as RootIsolateToken;
    BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

    ReceivePort imagePort = ReceivePort();
    sendPort.send(imagePort.sendPort);

    final FaceDetector _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableContours: true,
        enableClassification: true,
        enableTracking: true,
        performanceMode: FaceDetectorMode.accurate,
      ),
    );

    await for (var message in imagePort) {
      if (message is List) {
        if (message.isNotEmpty && message.length == 3) {
          if (message[0] is CameraImage &&
              message[1] is int &&
              message[2] is SendPort) {
            final CameraImage image = message[0];
            final int sensorOrientation = message[1];
            final SendPort sendMsg = message[2];

            InputImageFormat? inputImageFormat =
                InputImageFormatValue.fromRawValue(image.format.raw);
            if (inputImageFormat == null ||
                (Platform.isAndroid &&
                    inputImageFormat != InputImageFormat.nv21) ||
                (Platform.isIOS &&
                    inputImageFormat != InputImageFormat.bgra8888)) {
              continue;
            }

            if (image.planes.length != 1) {
              continue;
            }

            Plane plane = image.planes.first;

            InputImage inputImage = InputImage.fromBytes(
              bytes: plane.bytes,
              metadata: InputImageMetadata(
                size: Size(image.width.toDouble(), image.height.toDouble()),
                format: inputImageFormat,
                bytesPerRow: plane.bytesPerRow,
                rotation: InputImageRotation.rotation0deg,
              ),
            );

            List<Face> faces = await _faceDetector.processImage(inputImage);
            print('[Debug camera] faces : ${faces.length}');
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
            imglib.Image img = decodeNV21(inputImage);
            sendMsg.send([faces, img]);
          }
        }
      }
    }
  } catch (e) {
    print('[Error Camera] $e');
  }
}

imglib.Image decodeNV21(InputImage image) {
  final width = image.metadata!.size.width.toInt();
  final height = image.metadata!.size.height.toInt();

  Uint8List yuv420sp = image.bytes!;

  final outImg = imglib.Image(width: width, height: height);

  final int frameSize = width * height;

  for (int j = 0, yp = 0; j < height; j++) {
    int uvp = frameSize + (j >> 1) * width, u = 0, v = 0;
    for (int i = 0; i < width; i++, yp++) {
      int y = (0xff & yuv420sp[yp]) - 16;
      if (y < 0) y = 0;
      if ((i & 1) == 0) {
        v = (0xff & yuv420sp[uvp++]) - 128;
        u = (0xff & yuv420sp[uvp++]) - 128;
      }
      int y1192 = 1192 * y;
      int r = (y1192 + 1634 * v);
      int g = (y1192 - 833 * v - 400 * u);
      int b = (y1192 + 2066 * u);

      r = r.clamp(0, 262143);
      g = g.clamp(0, 262143);
      b = b.clamp(0, 262143);

      outImg.setPixelRgb(
        i,
        j,
        ((r << 6) & 0xff0000) >> 16,
        ((g >> 2) & 0xff00) >> 8,
        (b >> 10) & 0xff,
      );
    }
  }
  return outImg;
}

class APICamera {
  late CameraLensDirection _initialDirection;
  late List<CameraDescription> _cameras;
  int _camera_index = 0;
  CameraController? controller;
  late Isolate _isolate;
  late SendPort sendPort;
  final ReceivePort _receivePort = ReceivePort();
  bool _busy = false;
  bool _run = false;
  StreamController streamJpgController = StreamController.broadcast();
  StreamController streamDectectFaceController = StreamController.broadcast();

  APICamera(CameraLensDirection direction) {
    _initialDirection = direction;
  }

  Future<void> init(RootIsolateToken rootIsolateToken) async {
    try {
      ReceivePort myReceivePort = ReceivePort();
      _isolate = await Isolate.spawn(processImage, [
        myReceivePort.sendPort,
        rootIsolateToken,
      ]);
      print('[Debug] * * * * *');
      sendPort = await myReceivePort.first;
      print('[Debug] * * * * * * * * * *');
      _receivePort.listen((message) {
        print('[Debug camera] finish process image');
        if (message is List) {
          print('[Debug camera] finish process image * ');
          if (message.isNotEmpty && message.length == 2) {
            print('[Debug camera] finish process image * * ');
            if (message[0] is List<Face> && message[1] is imglib.Image) {
              final List<Face> faces = message[0];
              final imglib.Image img = message[1];
              print('[Debug] size : ${faces.length}');
              streamDectectFaceController.sink.add([faces, img]);
              _busy = false;
            }
          }
        }
      });
      _busy = false;
      _run = false;
    } catch (e) {
      print('[Error Camera] $e');
    }
  }

  Future<void> start() async {
    if (_run == false) {
      try {
        _cameras = await availableCameras();
        _camera_index = 0;
        if (_cameras.any(
          (element) =>
              element.lensDirection == _initialDirection &&
              element.sensorOrientation == 99,
        )) {
          _camera_index = _cameras.indexOf(
            _cameras.firstWhere(
              (element) =>
                  element.lensDirection == _initialDirection &&
                  element.sensorOrientation == 99,
            ),
          );
        } else {
          _camera_index = _cameras.indexOf(
            _cameras.firstWhere(
              (element) => element.lensDirection == _initialDirection,
            ),
          );
        }
        if (_cameras[_camera_index] != null) {
          if (controller != null) {
            await controller!.stopImageStream();
            controller = null;
          }
          controller = CameraController(
            _cameras[_camera_index],
            ResolutionPreset.low,
            enableAudio: false,
            imageFormatGroup: ImageFormatGroup.nv21,
          );
          if (controller != null) {
            try {
              await controller!.initialize();
              controller!.startImageStream((value) {
                CameraImage image = value;
                int sensorOrientation =
                    _cameras[_camera_index].sensorOrientation;
                if (_busy == false) {
                  _busy = true;
                  print('[Debug camera] start process image');
                  if (sendPort == null) {
                    print('[Debug camera] start process image * ');
                  }
                  sendPort.send([
                    image,
                    sensorOrientation,
                    _receivePort.sendPort,
                  ]);
                }
              });
              _run = true;
            } on CameraException catch (e) {
              switch (e.code) {
                case 'CameraAccessDenied':
                  print('You have denied camera access.');
                  break;
                case 'CameraAccessDeniedWithoutPrompt':
                  print('Please go to Settings app to enable camera access.');
                  break;
                case 'CameraAccessRestricted':
                  print('Camera access is restricted.');
                  break;
                case 'AudioAccessDenied':
                  print('You have denied audio access.');
                  break;
                case 'AudioAccessDeniedWithoutPrompt':
                  print('Please go to Settings app to enable audio access.');
                  break;
                case 'AudioAccessRestricted':
                  print('Audio access is restricted.');
                  break;
                default:
                  print(e);
                  break;
              }
            }
          }
        }
      } catch (e) {
        print('[Error Camera] $e');
      }
    }
  }

  Future<void> stop() async {
    if (_run == true) {
      try {
        if (controller != null) {
          await controller!.stopImageStream();
          await controller!.dispose();
          controller = null;
          _run = false;
        }
      } catch (e) {
        print('[Debug] : $e');
      }
    }
  }

  bool state() {
    return _run;
  }

  imglib.Image convertYUV420(CameraImage cameraImage) {
    final imageWidth = cameraImage.width;
    final imageHeight = cameraImage.height;
    final yBuffer = cameraImage.planes[0].bytes;
    final uBuffer = cameraImage.planes[1].bytes;
    final vBuffer = cameraImage.planes[2].bytes;
    final int yRowStride = cameraImage.planes[0].bytesPerRow;
    final int yPixelStride = cameraImage.planes[0].bytesPerPixel!;
    final int uvRowStride = cameraImage.planes[1].bytesPerRow;
    final int uvPixelStride = cameraImage.planes[1].bytesPerPixel!;
    final image = imglib.Image(width: imageWidth, height: imageHeight);

    for (int h = 0; h < imageHeight; h++) {
      int uvh = (h / 2).floor();
      for (int w = 0; w < imageWidth; w++) {
        int uvw = (w / 2).floor();
        final yIndex = (h * yRowStride) + (w * yPixelStride);
        final int y = yBuffer[yIndex];
        final int uvIndex = (uvh * uvRowStride) + (uvw * uvPixelStride);
        final int u = uBuffer[uvIndex];
        final int v = vBuffer[uvIndex];
        int r = (y + v * 1436 / 1024 - 179).round();
        int g = (y - u * 46549 / 131072 + 44 - v * 93604 / 131072 + 91).round();
        int b = (y + u * 1814 / 1024 - 227).round();
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        image.setPixelRgba(w, h, r, g, b, 255);
      }
    }
    return image;
  }

  imglib.Image convertBGRA8888(CameraImage image) {
    return imglib.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
    );
  }

  Uint8List convertJPG(imglib.Image image) {
    return Uint8List.fromList(imglib.encodeJpg(image, quality: 90));
  }
}

class InfoPerson {
  String id = "";
  String name = "";
  String phone = "";
  String faceId = "";
  double angleX = 0;
  double angleY = 0;
  double angleZ = 0;
  double x = 0;
  double y = 0;
  double w = 0;
  double h = 0;

  Uint8List image = Uint8List(0);
  int lastest = DateTime.now().millisecondsSinceEpoch;
  int timecheck = 1;
  bool busy = false;
  bool check = false;

  void update(InfoPerson other) {
    this.id = other.id;
    this.name = other.name;
    this.phone = other.phone;
    this.faceId = other.faceId;
    this.angleX = other.angleX;
    this.angleY = other.angleY;
    this.angleZ = other.angleZ;
    this.x = other.x;
    this.y = other.y;
    this.w = other.w;
    this.h = other.h;
    this.image = other.image;
    this.lastest = DateTime.now().millisecondsSinceEpoch;
    this.timecheck = other.timecheck;
    this.busy = other.busy;
    this.check = other.check;
  }
}

class APIFace {
  List<InfoPerson> persons = [];

  double s_x1 = 0.6;
  double s_x2 = 0.6;
  double s_y1 = 0.75;
  double s_y2 = 0.85;

  late APICamera camera;

  StreamController streamPersonController = StreamController.broadcast();

  APIFace() {
    camera = APICamera(CameraLensDirection.front);
  }

  void init(RootIsolateToken rootIsolateToken) {
    camera.init(rootIsolateToken);

    camera.streamDectectFaceController.stream.listen((event) {
      if (event is List) {
        if (event[0] is List<Face> && event[1] is imglib.Image) {
          List<Face> faces = event[0];
          print('[Debug face] Size : ${faces.length}');
          imglib.Image img = event[1];

          if (faces.length > 0) {
            for (int i = 0; i < faces.length; i++) {
              print('[Debug face] Info Face : $i - ${faces[i].trackingId}');
              if (faces[i].trackingId != null) {
                if (persons.length > 0) {
                  bool flag = false;
                  for (int j = 0; j < persons.length; j++) {
                    if (persons[j].faceId.compareTo(
                              faces[i].trackingId!.toString(),
                            ) ==
                        0) {
                      persons[j].lastest =
                          DateTime.now().millisecondsSinceEpoch;
                      persons[j].angleX = faces[i].headEulerAngleX ?? 0;
                      persons[j].angleY = faces[i].headEulerAngleY ?? 0;
                      persons[j].angleZ = faces[i].headEulerAngleZ ?? 0;
                      persons[j].x = faces[i].boundingBox.center.dx;
                      persons[j].y = faces[i].boundingBox.center.dy;
                      persons[j].w = faces[i].boundingBox.width;
                      persons[j].h = faces[i].boundingBox.height;

                      if (persons[j].angleX.abs() < 45 &&
                          persons[j].angleY.abs() < 45 &&
                          persons[j].angleZ.abs() < 45) {
                        if (persons[j].busy == false) {
                          int x1 = (persons[j].x - persons[j].w * s_x1).toInt();
                          int y1 = (persons[j].y - persons[j].h * s_y1).toInt();
                          int x2 = (persons[j].x + persons[j].w * s_x2).toInt();
                          int y2 = (persons[j].y + persons[j].h * s_y2).toInt();

                          if (x1 < 0) {
                            x1 = 0;
                          }
                          if (y1 < 0) {
                            y1 = 0;
                          }
                          if (x2 > (img.width - 1)) {
                            x2 = img.width - 1;
                          }
                          if (y2 > (img.height - 1)) {
                            y2 = img.height - 1;
                          }

                          imglib.Image buffer = imglib.copyCrop(
                            img,
                            x: x1,
                            y: y1,
                            width: x2 - x1,
                            height: y2 - y1,
                          );
                          persons[j].image = Uint8List.fromList(
                            imglib.encodeJpg(buffer, quality: 90),
                          );
                          persons[j].busy = true;
                          persons[j].check = true;
                        }
                      }
                      flag = true;
                      break;
                    }
                  }

                  if (flag == false) {
                    print(
                      '[Debug face] Add : ${faces[i].trackingId!.toString()}',
                    );
                    InfoPerson info = InfoPerson();
                    info.faceId = faces[i].trackingId!.toString();
                    info.lastest = DateTime.now().millisecondsSinceEpoch;
                    info.angleX = faces[i].headEulerAngleX ?? 0;
                    info.angleY = faces[i].headEulerAngleY ?? 0;
                    info.angleZ = faces[i].headEulerAngleZ ?? 0;
                    info.x = faces[i].boundingBox.center.dx;
                    info.y = faces[i].boundingBox.center.dy;
                    info.w = faces[i].boundingBox.width;
                    info.h = faces[i].boundingBox.height;

                    if (info.angleX.abs() < 45 &&
                        info.angleY.abs() < 45 &&
                        info.angleZ.abs() < 45) {
                      int x1 = (info.x - info.w * s_x1).toInt();
                      int y1 = (info.y - info.h * s_y1).toInt();
                      int x2 = (info.x + info.w * s_x2).toInt();
                      int y2 = (info.y + info.h * s_y2).toInt();

                      if (x1 < 0) {
                        x1 = 0;
                      }
                      if (y1 < 0) {
                        y1 = 0;
                      }
                      if (x2 > (img.width - 1)) {
                        x2 = img.width - 1;
                      }
                      if (y2 > (img.height - 1)) {
                        y2 = img.height - 1;
                      }
                      imglib.Image buffer = imglib.copyCrop(
                        img,
                        x: x1,
                        y: y1,
                        width: x2 - x1,
                        height: y2 - y1,
                      );
                      info.image = Uint8List.fromList(
                        imglib.encodeJpg(buffer, quality: 90),
                      );
                      info.busy = true;
                      info.check = true;
                    }
                    persons.add(info);
                  }
                } else {
                  print(
                    '[Debug face] Add : ${faces[i].trackingId!.toString()}',
                  );
                  InfoPerson info = InfoPerson();
                  info.faceId = faces[i].trackingId!.toString();
                  info.lastest = DateTime.now().millisecondsSinceEpoch;
                  info.angleX = faces[i].headEulerAngleX ?? 0;
                  info.angleY = faces[i].headEulerAngleY ?? 0;
                  info.angleZ = faces[i].headEulerAngleZ ?? 0;
                  info.x = faces[i].boundingBox.center.dx;
                  info.y = faces[i].boundingBox.center.dy;
                  info.w = faces[i].boundingBox.width;
                  info.h = faces[i].boundingBox.height;

                  if (info.angleX.abs() < 45 &&
                      info.angleY.abs() < 45 &&
                      info.angleZ.abs() < 45) {
                    int x1 = (info.x - info.w * s_x1).toInt();
                    int y1 = (info.y - info.h * s_y1).toInt();
                    int x2 = (info.x + info.w * s_x2).toInt();
                    int y2 = (info.y + info.h * s_y2).toInt();

                    if (x1 < 0) {
                      x1 = 0;
                    }
                    if (y1 < 0) {
                      y1 = 0;
                    }
                    if (x2 > (img.width - 1)) {
                      x2 = img.width - 1;
                    }
                    if (y2 > (img.height - 1)) {
                      y2 = img.height - 1;
                    }
                    imglib.Image buffer = imglib.copyCrop(
                      img,
                      x: x1,
                      y: y1,
                      width: x2 - x1,
                      height: y2 - y1,
                    );
                    info.image = Uint8List.fromList(
                      imglib.encodeJpg(buffer, quality: 90),
                    );
                    info.busy = true;
                    info.check = true;
                  }
                  persons.add(info);
                }
              }
            }
          }

          if (persons.length > 0) {
            int m_time = DateTime.now().millisecondsSinceEpoch;
            for (int i = 0; i < persons.length; i++) {
              int tmp = m_time - persons[i].lastest;
              if (tmp > 1000) {
                persons.removeAt(i);
                i--;
              }
            }
          }

          print('[Debug face] : length ${persons.length}');

          if (persons.isNotEmpty) {
            print('[Debug face] : * length ${persons.length}');
            for (int i = 0; i < persons.length; i++) {
              if (persons[i].check == true) {
                int time = DateTime.now().millisecondsSinceEpoch -
                    persons[i].timecheck;
                if (time > 2000) {
                  print(
                    '[Debug face] : detected face ${i} : ${persons[i].faceId}',
                  );
                  print(
                    '[Face] : ${persons[i].faceId} - ${persons[i].lastest} | ${persons[i].angleX} , ${persons[i].angleY} , ${persons[i].angleZ} - ${persons[i].image.length} - ${persons[i].w} x ${persons[i].h}',
                  );
                  persons[i].busy = false;
                  persons[i].check = false;
                  persons[i].timecheck = DateTime.now().millisecondsSinceEpoch;
                  streamPersonController.sink.add([persons[i].faceId]);
                }
              } else {
                print(
                  '[Debug face] : dont detect face ${i} : ${persons[i].faceId}',
                );
              }
            }
          }
        }
      }
    });
  }

  Future<void> start() async {
    if (camera.state() == false) {
      persons.clear();
      await camera.start();
    }
  }

  void stop() {
    if (camera.state() == true) {
      camera.stop();
      persons.clear();
    }
  }

  bool state() {
    return camera.state();
  }

  List<String> findPerson() {
    if (persons.isNotEmpty) {
      int index = 0;
      double max = 0;
      for (int i = 0; i < persons.length; i++) {
        if (max < persons[i].w) {
          index = i;
          max = persons[i].w;
        }
      }
      List<String> result = [];
      result.add(persons[index].faceId);
      result.add(persons[index].id);
      result.add(persons[index].name);
      result.add(persons[index].phone);
      return result;
    } else {
      return [];
    }
  }
}
