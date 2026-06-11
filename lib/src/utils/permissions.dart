import 'package:permission_handler/permission_handler.dart';

Future<bool> requestCameraPermission() async {
  final status = await Permission.camera.request();
  return status.isGranted;
}

Future<bool> hasCameraPermission() async =>
    (await Permission.camera.status).isGranted;

/// Opens the OS app-settings page so the user can re-enable a permission they
/// previously denied (camera). Returns whether the settings page opened.
Future<bool> openDeviceAppSettings() => openAppSettings();
