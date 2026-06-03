import Flutter
import UIKit
import Vision
import CoreVideo

/// iOS face detection for the Myaza KYC Flutter SDK, via Apple's Vision
/// framework. Built into the core SDK package — no separate plugin and no
/// GoogleMLKit pod, so the SDK builds and runs on Apple-Silicon iOS simulators.
///
/// Receives one BGRA camera frame per call, runs `VNDetectFaceLandmarksRequest`,
/// and returns the gesture signals the Dart liveness flow expects: head pose
/// (degrees), eye-open + smile (0–1), and a normalized face-size ratio.
///
/// Heuristic note: yaw/pitch/roll come directly from Vision. Eye-open and smile
/// are derived from landmark geometry and mapped to 0–1 to match the SDK's
/// gesture thresholds. Those mappings, the front-camera `orientation`, and the
/// nod pitch sign are conservative starting points — calibrate on a device.
public class KycSdkFlutterPlugin: NSObject, FlutterPlugin {
  private let workQueue = DispatchQueue(label: "co.myazahq.kyc.vision", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/face_detection",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(KycSdkFlutterPlugin(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "detect":
      detect(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func detect(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let width = args["width"] as? Int,
      let height = args["height"] as? Int,
      let planes = args["planes"] as? [[String: Any]],
      let first = planes.first,
      let typed = first["bytes"] as? FlutterStandardTypedData,
      let bytesPerRow = first["bytesPerRow"] as? Int
    else {
      result(nil)
      return
    }
    let data = typed.data

    workQueue.async {
      guard
        let pixelBuffer = Self.makeBGRAPixelBuffer(
          data: data, width: width, height: height, bytesPerRow: bytesPerRow
        )
      else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      // Front camera, portrait. Simulators have no camera, so this matters only
      // on device — adjust if pose/landmarks look mirrored or rotated.
      let orientation: CGImagePropertyOrientation = .leftMirrored

      let request = VNDetectFaceLandmarksRequest()
      let handler = VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:]
      )

      do {
        try handler.perform([request])
      } catch {
        DispatchQueue.main.async { result(nil) }
        return
      }

      guard
        let faces = request.results, !faces.isEmpty,
        let face = faces.max(by: {
          ($0.boundingBox.width * $0.boundingBox.height)
            < ($1.boundingBox.width * $1.boundingBox.height)
        })
      else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      let toDeg = 180.0 / Double.pi
      let yawDeg = (face.yaw?.doubleValue ?? 0) * toDeg
      let rollDeg = (face.roll?.doubleValue ?? 0) * toDeg
      var pitchDeg = 0.0
      if #available(iOS 15.0, *) {
        pitchDeg = (face.pitch?.doubleValue ?? 0) * toDeg
      }

      let leftOpen = Self.openProbability(
        fromEAR: Self.eyeAspectRatio(face.landmarks?.leftEye))
      let rightOpen = Self.openProbability(
        fromEAR: Self.eyeAspectRatio(face.landmarks?.rightEye))
      let smile = Self.smileProbability(face.landmarks)
      let faceSizeRatio = Double(face.boundingBox.width)

      let payload: [String: Any] = [
        // NOTE: ML Kit's nod uses headEulerAngleX<0 == looking down. If nod
        // doesn't trigger on device, negate pitchDeg here.
        "headEulerAngleX": pitchDeg,
        "headEulerAngleY": yawDeg,
        "headEulerAngleZ": rollDeg,
        "smilingProbability": smile,
        "leftEyeOpenProbability": leftOpen,
        "rightEyeOpenProbability": rightOpen,
        "faceSizeRatio": faceSizeRatio,
      ]
      DispatchQueue.main.async { result(payload) }
    }
  }

  // MARK: - Pixel buffer

  private static func makeBGRAPixelBuffer(
    data: Data, width: Int, height: Int, bytesPerRow: Int
  ) -> CVPixelBuffer? {
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault, width, height,
      kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb
    )
    guard status == kCVReturnSuccess, let buffer = pb else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let dest = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let destBPR = CVPixelBufferGetBytesPerRow(buffer)

    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let src = raw.baseAddress else { return }
      if destBPR == bytesPerRow {
        memcpy(dest, src, min(data.count, destBPR * height))
      } else {
        let copyBytes = min(bytesPerRow, destBPR)
        for row in 0..<height {
          memcpy(
            dest.advanced(by: row * destBPR),
            src.advanced(by: row * bytesPerRow),
            copyBytes
          )
        }
      }
    }
    return buffer
  }

  // MARK: - Landmark heuristics (tune on device)

  private static func eyeAspectRatio(_ region: VNFaceLandmarkRegion2D?) -> Double {
    guard let pts = region?.normalizedPoints, pts.count >= 4 else { return 0.3 }
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    var minY = Double.greatestFiniteMagnitude
    var maxY = -Double.greatestFiniteMagnitude
    for p in pts {
      minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
      minY = min(minY, Double(p.y)); maxY = max(maxY, Double(p.y))
    }
    let w = maxX - minX
    let h = maxY - minY
    return w > 0 ? h / w : 0.3
  }

  /// EAR → eye-open probability. EAR ≈ 0.10 (closed) → 0, ≈ 0.30 (open) → 1.
  private static func openProbability(fromEAR ear: Double) -> Double {
    let v = (ear - 0.10) / (0.30 - 0.10)
    return min(max(v, 0.0), 1.0)
  }

  /// Smile from outer-lip width / face box. Neutral ≈ 0.42, smiling ≈ 0.55+.
  private static func smileProbability(_ landmarks: VNFaceLandmarks2D?) -> Double {
    guard let pts = landmarks?.outerLips?.normalizedPoints, pts.count >= 4 else {
      return 0.0
    }
    var minX = Double.greatestFiniteMagnitude
    var maxX = -Double.greatestFiniteMagnitude
    for p in pts {
      minX = min(minX, Double(p.x)); maxX = max(maxX, Double(p.x))
    }
    let width = maxX - minX
    let score = (width - 0.42) / (0.55 - 0.42)
    return min(max(score, 0.0), 1.0)
  }
}
