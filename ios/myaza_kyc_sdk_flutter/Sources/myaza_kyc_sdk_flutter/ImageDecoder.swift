import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Decodes image formats Flutter cannot render itself.
///
/// The one that matters is JPEG 2000: most passport chips store their portrait
/// (DG2) that way, and Flutter has no decoder for it. iOS does — ImageIO
/// registers `public.jpeg-2000` — so a frame the SDK could otherwise only
/// describe can actually be shown.
///
/// Returns JPEG bytes, which every platform renders. Failure returns nil rather
/// than throwing: the portrait is a courtesy preview and the chip read stands
/// on its own without it.
public class ImageDecoder: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "kyc_sdk_flutter/image_decode",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(ImageDecoder(), channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "decode",
          let args = call.arguments as? [String: Any],
          let data = args["bytes"] as? FlutterStandardTypedData
    else {
      result(FlutterMethodNotImplemented)
      return
    }

    // Off the main thread: a full-resolution portrait is a few hundred
    // kilobytes of wavelet data and decoding it should not stall a frame.
    DispatchQueue.global(qos: .userInitiated).async {
      let jpeg = Self.transcodeToJpeg(data.data)
      DispatchQueue.main.async {
        result(jpeg.map { FlutterStandardTypedData(bytes: $0) })
      }
    }
  }

  /// Decodes any format ImageIO understands and re-encodes as JPEG.
  static func transcodeToJpeg(_ data: Data, quality: CGFloat = 0.9) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { return nil }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: quality)
  }
}
