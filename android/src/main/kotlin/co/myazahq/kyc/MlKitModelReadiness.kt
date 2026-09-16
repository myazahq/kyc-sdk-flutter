package co.myazahq.kyc

import android.content.Context
import com.google.android.gms.common.api.OptionalModuleApi
import com.google.android.gms.common.moduleinstall.InstallStatusListener
import com.google.android.gms.common.moduleinstall.ModuleInstall
import com.google.android.gms.common.moduleinstall.ModuleInstallClient
import com.google.android.gms.common.moduleinstall.ModuleInstallRequest
import com.google.android.gms.common.moduleinstall.ModuleInstallStatusUpdate
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions

/**
 * Whether an ML Kit model can run right now, and a request to fetch it.
 *
 * The default build fetches both models through Play Services instead of
 * bundling them (android/build.gradle). The cost is a window where a detector
 * cannot run, and nothing in its own output can say so: a face detector with no
 * model finds no face, exactly as it does on an empty frame, and a text
 * recogniser with no model finds no lines, exactly as it does on a blank page.
 * So readiness is its own question, asked before a camera opens.
 *
 * Answers are "ready", "pending" or "failed", mirrored in Dart as
 * NativeModelStatus. "failed" is reserved for Play Services saying it cannot
 * deliver: no GMS on the device, or an install that failed or was cancelled. A
 * slow download is "pending", and the Dart gate decides how long to wait.
 *
 * The install is URGENT (`installModules`), not deferred: `deferredInstall`
 * leaves the timing to Play Services, which is right for a model somebody might
 * want next week and wrong for one a person is waiting on now.
 */
class MlKitModelReadiness(newApi: () -> OptionalModuleApi) {
  // A client built only to name the module. getClient() does not load the
  // model, so holding one costs nothing until something processes a frame.
  private val api: OptionalModuleApi by lazy(newApi)

  // Starts true on a bundled build, where the model is in the APK and Play
  // Services would wrongly report its optional module as missing.
  @Volatile private var ready = BuildConfig.BUNDLED_ML_KIT
  @Volatile private var failed = false
  @Volatile private var installing = false

  /**
   * Reports where the model stands. With [install], also requests the model
   * when it is absent, and clears an earlier failure so a new attempt can run.
   * [done] runs on the main thread, where Play Services delivers its callbacks.
   */
  fun status(context: Context, install: Boolean, done: (String) -> Unit) {
    if (ready) return done(READY)
    if (install) failed = false else if (failed) return done(FAILED)

    try {
      val client = ModuleInstall.getClient(context)
      client.areModulesAvailable(api)
        .addOnSuccessListener { response ->
          when {
            response.areModulesAvailable() -> {
              ready = true
              done(READY)
            }
            failed -> done(FAILED)
            else -> {
              if (install) requestInstall(client)
              done(PENDING)
            }
          }
        }
        // Thrown where there is no Google Play Services at all (Huawei, bare
        // AOSP). It will never succeed on this device, so it is not "pending".
        .addOnFailureListener {
          failed = true
          done(FAILED)
        }
    } catch (_: Throwable) {
      failed = true
      done(FAILED)
    }
  }

  private fun requestInstall(client: ModuleInstallClient) {
    if (installing) return
    installing = true

    val listener = object : InstallStatusListener {
      override fun onInstallStatusUpdated(update: ModuleInstallStatusUpdate) {
        when (update.installState) {
          ModuleInstallStatusUpdate.InstallState.STATE_COMPLETED -> {
            ready = true
            installing = false
            client.unregisterListener(this)
          }
          ModuleInstallStatusUpdate.InstallState.STATE_FAILED,
          ModuleInstallStatusUpdate.InstallState.STATE_CANCELED -> {
            failed = true
            installing = false
            client.unregisterListener(this)
          }
        }
      }
    }

    val request = ModuleInstallRequest.Builder().addApi(api).setListener(listener).build()
    client.installModules(request)
      .addOnSuccessListener { response ->
        // The listener never fires for a module that was already there.
        if (response.areModulesAlreadyInstalled()) {
          ready = true
          installing = false
          client.unregisterListener(listener)
        }
      }
      .addOnFailureListener {
        failed = true
        installing = false
        client.unregisterListener(listener)
      }
  }

  private companion object {
    const val READY = "ready"
    const val PENDING = "pending"
    const val FAILED = "failed"
  }
}

/** One gate per model, shared by every path that uses it: the method-channel
 *  detectors, the native liveness recorder and the native document camera. */
object MlKitModels {
  val face = MlKitModelReadiness { FaceDetection.getClient() }
  val text = MlKitModelReadiness { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
}
