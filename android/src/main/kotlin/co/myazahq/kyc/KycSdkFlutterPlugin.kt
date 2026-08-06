package co.myazahq.kyc

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry

/**
 * Android side of the Myaza KYC SDK. Four responsibilities, each in its own
 * class; this file only owns the channels and routes calls to them.
 *
 *  1. **Per-frame face detection** (`kyc_sdk_flutter/face_detection`) →
 *     [FaceDetectorHandler]. Dart sends an NV21 frame, we return ML Kit face
 *     signals. Used by code paths that drive their own camera (the Flutter
 *     camera-plugin liveness path, kept as a fallback).
 *
 *  2. **Text recognition** (`kyc_sdk_flutter/text_recognition`) →
 *     [TextRecognizerHandler]. One frame or one still in, recognized lines out.
 *
 *  3. **Native liveness recorder** (`kyc_sdk_flutter/liveness_recorder` +
 *     `…/faces`) → [LivenessRecorder]. Owns the camera via CameraX, running ONE
 *     ImageAnalysis stream fanned to both ML Kit and a MediaCodec encoder.
 *
 *  4. **Native document camera** (`kyc_sdk_flutter/document_camera` + `…/text`)
 *     → [DocumentCameraHandler]. The same single-session approach for the
 *     document step, replacing the Flutter camera plugin there on Android.
 *
 * Keeping ML Kit Android-only (Gradle) means no GoogleMLKit CocoaPod on iOS, so
 * the SDK still builds for Apple-Silicon iOS simulators (iOS uses Apple Vision).
 */
class KycSdkFlutterPlugin : FlutterPlugin, MethodCallHandler {
  private lateinit var channel: MethodChannel
  private lateinit var recorderChannel: MethodChannel
  private lateinit var textChannel: MethodChannel
  private lateinit var faceEventChannel: EventChannel

  private val faceDetector = FaceDetectorHandler()
  private val textRecognizer = TextRecognizerHandler()
  private var documentCamera: DocumentCameraHandler? = null

  private lateinit var appContext: Context
  private lateinit var textures: TextureRegistry
  private val mainHandler = Handler(Looper.getMainLooper())

  private var faceSink: EventChannel.EventSink? = null
  private var recorder: LivenessRecorder? = null

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    textures = binding.textureRegistry

    channel = MethodChannel(binding.binaryMessenger, "kyc_sdk_flutter/face_detection")
    channel.setMethodCallHandler(this)

    recorderChannel = MethodChannel(binding.binaryMessenger, "kyc_sdk_flutter/liveness_recorder")
    recorderChannel.setMethodCallHandler(this)

    textChannel = MethodChannel(binding.binaryMessenger, "kyc_sdk_flutter/text_recognition")
    textChannel.setMethodCallHandler(this)

    faceEventChannel = EventChannel(binding.binaryMessenger, "kyc_sdk_flutter/liveness_recorder/faces")
    faceEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        faceSink = events
      }
      override fun onCancel(arguments: Any?) {
        faceSink = null
      }
    })

    documentCamera = DocumentCameraHandler(appContext, textures, binding.binaryMessenger)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    recorderChannel.setMethodCallHandler(null)
    textChannel.setMethodCallHandler(null)
    textRecognizer.close()
    faceEventChannel.setStreamHandler(null)
    documentCamera?.detach()
    documentCamera = null
    recorder?.dispose()
    recorder = null
    faceDetector.close()
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "detect" -> faceDetector.detect(call, result)
      "recognize" -> textRecognizer.recognize(call, result)
      "recognizeBytes" -> textRecognizer.recognizeBytes(call, result)
      "startRecorder" -> handleStartRecorder(result)
      "startRecording" -> {
        recorder?.startRecording()
        result.success(null)
      }
      "stopRecording" -> {
        val path = recorder?.stopRecording()
        result.success(path)
      }
      "captureStill" -> {
        val q = call.argument<Int>("quality") ?: 90
        result.success(recorder?.captureStillJpeg(q))
      }
      "disposeRecorder" -> {
        recorder?.dispose()
        recorder = null
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  // ── Native liveness recorder ────────────────────────────────────────────────

  private fun handleStartRecorder(result: Result) {
    recorder?.dispose()
    recorder = null

    val rec = LivenessRecorder(appContext, textures) { payload ->
      // Stream face signals to Dart on the main thread.
      mainHandler.post { faceSink?.success(payload) }
    }
    recorder = rec
    rec.start(
      onReady = { textureId ->
        mainHandler.post {
          result.success(
            mapOf(
              "textureId" to textureId,
              "rotation" to rec.rotationDegrees,
              "previewWidth" to rec.previewBufferWidth,
              "previewHeight" to rec.previewBufferHeight,
            ),
          )
        }
      },
      onError = { msg -> mainHandler.post { result.error("recorder_start_failed", msg, null) } },
    )
  }
}
