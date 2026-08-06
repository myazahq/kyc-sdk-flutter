package co.myazahq.kyc

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Channel plumbing for the native document camera ([DocumentCamera]).
 *
 *  * method channel `kyc_sdk_flutter/document_camera` — start / record / capture
 *    / dispose
 *  * event channel `kyc_sdk_flutter/document_camera/text` — the recognized text
 *    lines of each analysed frame, which drive Dart's auto-capture gate
 *
 * Self-contained (owns its channels) so [KycSdkFlutterPlugin] only wires it up.
 */
class DocumentCameraHandler(
  private val context: Context,
  private val textures: TextureRegistry,
  messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

  private val method = MethodChannel(messenger, "kyc_sdk_flutter/document_camera")
  private val events = EventChannel(messenger, "kyc_sdk_flutter/document_camera/text")
  private val mainHandler = Handler(Looper.getMainLooper())

  private var textSink: EventChannel.EventSink? = null
  private var camera: DocumentCamera? = null

  init {
    method.setMethodCallHandler(this)
    events.setStreamHandler(object : EventChannel.StreamHandler {
      override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        textSink = sink
      }

      override fun onCancel(arguments: Any?) {
        textSink = null
      }
    })
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "start" -> start(result)
      "startRecording" -> {
        camera?.startRecording()
        result.success(null)
      }
      "stopRecording" -> result.success(camera?.stopRecording())
      "captureStill" -> captureStill(call, result)
      "hasTorch" -> result.success(camera?.hasTorch() ?: false)
      "setTorch" -> {
        camera?.setTorch(call.argument<Boolean>("enabled") ?: false)
        result.success(null)
      }
      "dispose" -> {
        camera?.dispose()
        camera = null
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun start(result: MethodChannel.Result) {
    camera?.dispose()
    camera = null

    val cam = DocumentCamera(context, textures) { payload ->
      mainHandler.post { textSink?.success(payload) }
    }
    camera = cam
    cam.start(
      onReady = {
        mainHandler.post {
          result.success(
            mapOf(
              "textureId" to cam.textureId,
              "rotation" to cam.rotationDegrees,
              "previewWidth" to cam.previewBufferWidth,
              "previewHeight" to cam.previewBufferHeight,
            ),
          )
        }
      },
      onError = { msg ->
        mainHandler.post { result.error("document_camera_start_failed", msg, null) }
      },
    )
  }

  private fun captureStill(call: MethodCall, result: MethodChannel.Result) {
    val cam = camera
    if (cam == null) {
      result.success(null)
      return
    }
    val quality = call.argument<Int>("quality") ?: 95
    // The capture callback arrives on the camera's analysis executor — every
    // MethodChannel.Result must be answered on the main thread.
    cam.captureStill(quality) { bytes -> mainHandler.post { result.success(bytes) } }
  }

  /** Releases the camera + channels when the engine detaches. */
  fun detach() {
    method.setMethodCallHandler(null)
    events.setStreamHandler(null)
    textSink = null
    camera?.dispose()
    camera = null
  }
}
