import Flutter
import UIKit
import Vision

/// On-device text recognition for MRZ scanning, via Apple's Vision framework.
///
/// Registered on its own channel so it stays independent of face detection, and
/// like that plugin it pulls no third-party pod — iOS-simulator builds stay
/// green.
///
/// Two settings matter for MRZ and are deliberate:
///   • `usesLanguageCorrection = false` — the MRZ is not natural language.
///     Correction "fixes" filler runs (`<<<<`) and check digits into words,
///     which destroys exactly the characters we need.
///   • `.accurate` — MRZ glyphs are small and dense; `.fast` misreads them
///     badly enough that the check digits never validate.
public class TextRecognizer: NSObject, FlutterPlugin {
  private let workQueue = DispatchQueue(label: "co.myazahq.kyc.ocr", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/text_recognition",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(TextRecognizer(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "recognize":
      recognize(call, result)
    case "recognizeBytes":
      recognizeBytes(call, result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func recognize(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
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
        let pixelBuffer = KycSdkFlutterPlugin.makeBGRAPixelBuffer(
          data: data, width: width, height: height, bytesPerRow: bytesPerRow
        )
      else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      // The camera delivers landscape sensor frames while the scan UI is
      // portrait, so `.right` is the usual correction. A document held the
      // other way up still needs to work, so fall back to the other
      // orientations until one yields MRZ-looking text.
      let orientations: [CGImagePropertyOrientation] = [.right, .up, .left, .down]
      var best: [String] = []

      for orientation in orientations {
        let lines = Self.recognizeLines(pixelBuffer, orientation)
        if Self.containsMrzCandidate(lines) {
          best = lines
          break
        }
        if best.isEmpty { best = lines }
      }

      let payload: [String: Any] = ["lines": best]
      DispatchQueue.main.async { result(payload) }
    }
  }

  /// Recognizes an encoded still (JPEG/PNG). Used to pull the MRZ out of the
  /// document photo the user already captured, so the chip step needs no second
  /// camera pass. A still is already upright, so no orientation sweep.
  private func recognizeBytes(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let typed = args["bytes"] as? FlutterStandardTypedData
    else {
      result(nil)
      return
    }
    let data = typed.data

    workQueue.async {
      let handler = VNImageRequestHandler(data: data, options: [:])
      let lines = Self.perform(handler)
      DispatchQueue.main.async { result(["lines": lines]) }
    }
  }

  private static func recognizeLines(
    _ buffer: CVPixelBuffer, _ orientation: CGImagePropertyOrientation
  ) -> [String] {
    let handler = VNImageRequestHandler(
      cvPixelBuffer: buffer, orientation: orientation, options: [:]
    )
    return perform(handler)
  }

  private static func perform(_ handler: VNImageRequestHandler) -> [String] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = false
    request.recognitionLanguages = ["en-US"]

    do {
      try handler.perform([request])
    } catch {
      return []
    }

    guard let observations = request.results else { return [] }
    return observations.compactMap { $0.topCandidates(1).first?.string }
  }

  /// Cheap pre-filter mirroring the Dart side: MRZ lines are filler-padded, so
  /// a run of `<` is the signal that this orientation found the right thing.
  private static func containsMrzCandidate(_ lines: [String]) -> Bool {
    for line in lines {
      let squashed = line.uppercased().filter { $0.isLetter || $0.isNumber || $0 == "<" }
      if squashed.count >= 28 && squashed.filter({ $0 == "<" }).count >= 2 {
        return true
      }
    }
    return false
  }
}
