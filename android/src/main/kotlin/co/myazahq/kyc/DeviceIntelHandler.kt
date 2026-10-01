package co.myazahq.kyc

import android.annotation.SuppressLint
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Device Intelligence, Android half (`kyc_sdk_flutter/device_intel`). Serves the
 * mobile fingerprint additions of kyc-core docs/DEVICE_INTEL_WIRE.md:
 *
 *  - `stableId`: `Settings.Secure.ANDROID_ID` (per signing key + user + device,
 *    survives a reinstall on Android 8+). No permission.
 *  - `integrity`: root / hook heuristics ([DeviceIntegrity]), off the main thread.
 *  - `playIntegrityToken`: a Play Integrity Standard API token ([PlayIntegrity]).
 *
 * App Attest is iOS-only, so `appAttestState` / `appAttest` are not implemented
 * here and the Dart side reads that as "skip". Every failure answers null.
 */
class DeviceIntelHandler(context: Context, messenger: BinaryMessenger) :
  MethodChannel.MethodCallHandler {

  private val appContext = context.applicationContext
  private val channel = MethodChannel(messenger, "kyc_sdk_flutter/device_intel")
  private val worker: ExecutorService = Executors.newSingleThreadExecutor()
  private val main = Handler(Looper.getMainLooper())
  private val playIntegrity = PlayIntegrity(appContext)

  init {
    channel.setMethodCallHandler(this)
  }

  fun detach() {
    channel.setMethodCallHandler(null)
    worker.shutdown()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "stableId" -> result.success(androidId())
      "integrity" -> worker.execute {
        val answer = try { DeviceIntegrity.check(appContext) } catch (_: Throwable) { null }
        main.post { result.success(answer) }
      }
      "playIntegrityToken" -> {
        val project = call.argument<String>("cloudProjectNumber")?.toLongOrNull()
        val hash = call.argument<String>("requestHash")
        if (project == null || hash.isNullOrEmpty()) {
          result.success(null)
        } else {
          playIntegrity.token(project, hash) { token -> main.post { result.success(token) } }
        }
      }
      else -> result.notImplemented()
    }
  }

  // ANDROID_ID is exactly what the contract asks for; the lint is about ad ids.
  @SuppressLint("HardwareIds")
  private fun androidId(): String? = try {
    Settings.Secure.getString(appContext.contentResolver, Settings.Secure.ANDROID_ID)
      ?.takeIf { it.isNotBlank() }
  } catch (_: Throwable) {
    null
  }
}
