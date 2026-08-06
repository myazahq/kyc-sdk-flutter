import 'dart:io';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Camera authorization, asked of AVFoundation directly on iOS.
///
/// `permission_handler` compiles each iOS permission behind a macro that
/// defaults to 0, so unless the HOST app adds `PERMISSION_CAMERA=1` to its
/// Podfile it reports the camera as denied even when access is granted — which
/// made the "allow camera access" primer reappear on every capture step. An SDK
/// can't require consumers to patch their Podfile for a core screen to behave,
/// so iOS goes through the SDK's own plugin channel.
///
/// It also means the pre-check and the camera open now read the SAME
/// authorization, so they can no longer disagree.
///
/// Android has no such macro system and `permission_handler` reads the real
/// grant, so it stays on the plugin there.
const MethodChannel _channel =
    MethodChannel('kyc_sdk_flutter/camera_permission');

Future<bool> requestCameraPermission() async {
  final status = await Permission.camera.request();
  return status.isGranted;
}

/// Whether the camera is already usable — i.e. the OS will NOT prompt.
///
/// Fails CLOSED: anything unexpected reports "not granted", which at worst
/// shows one extra explanatory screen before a prompt that may not come. The
/// opposite default would open the camera with no warning at all.
Future<bool> hasCameraPermission() async {
  if (Platform.isIOS) {
    try {
      return await _channel.invokeMethod<String>('status') == 'granted';
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // Host app running an older embedded build without this channel.
      return false;
    }
  }
  return (await Permission.camera.status).isGranted;
}

/// Opens the OS app-settings page so the user can re-enable a permission they
/// previously denied (camera). Returns whether the settings page opened.
///
/// Not behind a permission macro — this one works without host configuration.
Future<bool> openDeviceAppSettings() => openAppSettings();
