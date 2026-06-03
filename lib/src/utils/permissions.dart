import 'package:permission_handler/permission_handler.dart';

Future<bool> requestCameraPermission() async {
  final status = await Permission.camera.request();
  return status.isGranted;
}

Future<bool> hasCameraPermission() async =>
    (await Permission.camera.status).isGranted;
