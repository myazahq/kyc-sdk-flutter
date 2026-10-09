package co.myazahq.kyc

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Asks Android for "Allow all the time" location, the permission the
 * background presence tier needs.
 *
 * Native on purpose. The geolocator plugin asks for background location in
 * the SAME request as the foreground permissions, and from Android 11 the
 * system ignores a request that mixes the two: nothing was shown and nothing
 * was granted (Galaxy S24, Android 16, 2026-10-04). Background location has
 * to be requested alone, after the foreground permission is held.
 *
 * On Android 11 and later the system answers this request by opening the
 * app's location settings page, where the person picks "Allow all the time".
 * After two refusals it answers at once without showing anything, and the
 * host sends the person to Settings itself.
 */
class PresenceAlwaysPermission : PluginRegistry.RequestPermissionsResultListener {
  private var activity: Activity? = null
  private var binding: ActivityPluginBinding? = null
  private var pending: Result? = null

  fun attach(binding: ActivityPluginBinding) {
    this.binding = binding
    activity = binding.activity
    binding.addRequestPermissionsResultListener(this)
  }

  fun detach() {
    binding?.removeRequestPermissionsResultListener(this)
    binding = null
    activity = null
    // A request cut off by the activity going away is answered, never left
    // hanging: null tells Dart to keep the permission it already knew.
    pending?.success(null)
    pending = null
  }

  private fun granted(activity: Activity, permission: String): Boolean =
    ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED

  private fun declared(activity: Activity): Boolean = try {
    @Suppress("DEPRECATION")
    val info = activity.packageManager.getPackageInfo(
      activity.packageName, PackageManager.GET_PERMISSIONS,
    )
    info.requestedPermissions?.contains(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == true
  } catch (_: Exception) {
    false
  }

  /** Answers "always", "whileInUse", "denied", or null when it cannot ask. */
  fun request(result: Result) {
    val activity = this.activity
    if (activity == null) {
      result.success(null)
      return
    }
    val foreground = granted(activity, Manifest.permission.ACCESS_FINE_LOCATION) ||
      granted(activity, Manifest.permission.ACCESS_COARSE_LOCATION)
    if (!foreground) {
      result.success("denied")
      return
    }
    // Before Android 10 there is no separate background permission.
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
      granted(activity, Manifest.permission.ACCESS_BACKGROUND_LOCATION)
    ) {
      result.success("always")
      return
    }
    // Undeclared by the host, or a request already on screen: nothing to ask.
    if (!declared(activity) || pending != null) {
      result.success("whileInUse")
      return
    }
    pending = result
    ActivityCompat.requestPermissions(
      activity, arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION), REQUEST_CODE,
    )
  }

  override fun onRequestPermissionsResult(
    requestCode: Int,
    permissions: Array<out String>,
    grantResults: IntArray,
  ): Boolean {
    if (requestCode != REQUEST_CODE) return false
    val result = pending ?: return true
    pending = null
    val ok = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
    result.success(if (ok) "always" else "whileInUse")
    return true
  }

  companion object {
    private const val REQUEST_CODE = 46291
  }
}
