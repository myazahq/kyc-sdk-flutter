import Flutter
import UIKit
import Vision

/// On-device document-edge detection for auto-capture, via Apple Vision.
///
/// Two requests, in preference order:
///   • `VNDetectDocumentSegmentationRequest` (iOS 15+) — purpose-built for
///     documents; returns a quad even against a low-contrast background and
///     copes with perspective.
///   • `VNDetectRectanglesRequest` — the fallback on iOS 13/14. Needs more
///     contrast and reports more false positives, hence the tighter aspect and
///     confidence bounds below.
///
/// Returns the document's normalized bounding box; the Dart side decides
/// whether that's centred and large enough to capture. Keeping the policy in
/// Dart means the thresholds are tunable without a native rebuild.
public class DocumentDetector: NSObject, FlutterPlugin {
  private let workQueue = DispatchQueue(label: "co.myazahq.kyc.docdetect", qos: .userInitiated)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/document_detection",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(DocumentDetector(), channel: channel)
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
        let pixelBuffer = KycSdkFlutterPlugin.makeBGRAPixelBuffer(
          data: data, width: width, height: height, bytesPerRow: bytesPerRow
        )
      else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      // The camera delivers landscape sensor frames while the capture UI is
      // portrait — same correction the text recognizer uses.
      let handler = VNImageRequestHandler(
        cvPixelBuffer: pixelBuffer, orientation: .right, options: [:]
      )

      // `.right` rotates the landscape sensor frame into the portrait UI, so
      // the ORIENTED pixel dimensions swap. The Dart side compares the
      // document's true aspect against the expected ID aspect, and that
      // comparison is meaningless without this swap.
      let orientedWidth = Double(height)
      let orientedHeight = Double(width)

      var payload: [String: Any]? = nil
      if #available(iOS 15.0, *) {
        payload = Self.segmentation(handler)
      }
      if payload == nil {
        payload = Self.rectangle(handler)
      }

      if var p = payload,
         let w = p["width"] as? Double,
         let h = p["height"] as? Double,
         w > 0, h > 0 {
        p["aspectRatio"] = (w * orientedWidth) / (h * orientedHeight)
        payload = p
      }

      // Brightness always rides along, INCLUDING when nothing was detected —
      // "too dark to see anything" is precisely the case where the user needs
      // to be told, and a nil payload could never carry that.
      var out = payload ?? [:]
      out["brightness"] = Self.meanBrightness(
        data: data, width: width, height: height, bytesPerRow: bytesPerRow
      )
      DispatchQueue.main.async { result(out) }
    }
  }

  @available(iOS 15.0, *)
  private static func segmentation(_ handler: VNImageRequestHandler) -> [String: Any]? {
    let request = VNDetectDocumentSegmentationRequest()
    do {
      try handler.perform([request])
    } catch {
      return nil
    }
    guard let best = request.results?.first else { return nil }
    return box(best.boundingBox, confidence: Double(best.confidence), source: "segmentation")
  }

  private static func rectangle(_ handler: VNImageRequestHandler) -> [String: Any]? {
    let request = VNDetectRectanglesRequest()
    // An ID card is ~1.586:1 and a passport page ~1.42:1; allow a wide band so
    // perspective doesn't reject a valid document, but not so wide that a
    // laptop edge or table qualifies.
    request.minimumAspectRatio = 0.5
    request.maximumAspectRatio = 1.0
    request.minimumSize = 0.3
    request.minimumConfidence = 0.6
    request.maximumObservations = 1

    do {
      try handler.perform([request])
    } catch {
      return nil
    }
    guard let best = request.results?.first else { return nil }
    return box(best.boundingBox, confidence: Double(best.confidence), source: "rectangle")
  }

  /// Mean luma over a coarse grid of the BGRA frame, 0..1. Sampled rather than
  /// summed: this runs per frame beside detection, and a full pass would cost
  /// more than the detection it accompanies for no extra accuracy.
  private static func meanBrightness(
    data: Data, width: Int, height: Int, bytesPerRow: Int
  ) -> Double {
    let stepX = max(1, width / 32)
    let stepY = max(1, height / 32)
    var total = 0.0
    var count = 0

    data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
      guard let base = raw.baseAddress else { return }
      let bytes = base.assumingMemoryBound(to: UInt8.self)
      var y = 0
      while y < height {
        var x = 0
        while x < width {
          let offset = y * bytesPerRow + x * 4
          guard offset + 2 < raw.count else { break }
          // BGRA
          let b = Double(bytes[offset])
          let g = Double(bytes[offset + 1])
          let r = Double(bytes[offset + 2])
          total += (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
          count += 1
          x += stepX
        }
        y += stepY
      }
    }
    return count == 0 ? 0.5 : total / Double(count)
  }

  /// Vision's origin is bottom-left; Flutter's is top-left. Flip Y so the Dart
  /// side can compare directly against its own guide rect.
  private static func box(
    _ rect: CGRect, confidence: Double, source: String
  ) -> [String: Any] {
    return [
      "x": Double(rect.origin.x),
      "y": Double(1.0 - rect.origin.y - rect.size.height),
      "width": Double(rect.size.width),
      "height": Double(rect.size.height),
      "confidence": confidence,
      "source": source,
    ]
  }
}
