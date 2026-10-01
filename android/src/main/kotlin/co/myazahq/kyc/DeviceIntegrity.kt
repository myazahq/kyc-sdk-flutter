package co.myazahq.kyc

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Debug
import java.io.File
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Client-side root and hook heuristics for `fingerprint.integrity`
 * (kyc-core docs/DEVICE_INTEL_WIRE.md §2). Soft by design: the server reads a
 * positive as evidence and a negative as nothing, so each check favours being
 * cheap and quiet over being clever. None prompts the user or needs a
 * permission. Run off the main thread (one check opens a loopback socket).
 *
 * Package checks see only what Android's package visibility allows without a
 * `<queries>` entry, so on Android 11+ `root_apps` mostly cannot fire. That is
 * deliberate: declaring those queries would change every host's manifest.
 */
object DeviceIntegrity {
  private val SU_PATHS = listOf(
    "/system/bin/su", "/system/xbin/su", "/sbin/su", "/su/bin/su",
    "/system/sd/xbin/su", "/system/bin/failsafe/su", "/data/local/su",
    "/data/local/bin/su", "/data/local/xbin/su", "/vendor/bin/su",
  )
  private val MAGISK_PATHS = listOf(
    "/sbin/.magisk", "/data/adb/magisk", "/data/adb/modules",
    "/cache/.disable_magisk", "/dev/.magisk.unblock",
  )
  private val BUSYBOX_PATHS = listOf(
    "/system/xbin/busybox", "/system/bin/busybox", "/sbin/busybox",
  )
  private val ROOT_APPS = listOf(
    "com.topjohnwu.magisk", "eu.chainfire.supersu", "com.koushikdutta.superuser",
    "com.noshufou.android.su", "com.thirdparty.superuser", "com.kingroot.kinguser",
    "me.weishu.kernelsu",
  )
  // Partitions that are read-only on a stock device. "/" is left out: older
  // devices mount a writable ramdisk there.
  private val SYSTEM_MOUNTS = setOf("/system", "/system/bin", "/system/xbin", "/vendor")
  private const val FRIDA_PORT = 27042

  private val ROOT_TOKENS = setOf(
    "su_binary", "magisk", "test_keys", "busybox", "root_apps", "writable_system",
  )
  private val HOOK_TOKENS = setOf("frida", "debugger")

  fun check(context: Context): Map<String, Any?> {
    val pm = context.packageManager
    val signals = mutableListOf<String>()
    // One failing heuristic must not cost the rest.
    fun probe(token: String, test: () -> Boolean) {
      try { if (test()) signals.add(token) } catch (_: Throwable) {}
    }

    probe("su_binary") { SU_PATHS.any { File(it).exists() } }
    probe("magisk") {
      MAGISK_PATHS.any { File(it).exists() } || installed(pm, "com.topjohnwu.magisk")
    }
    probe("test_keys") { Build.TAGS?.contains("test-keys") == true }
    probe("busybox") { BUSYBOX_PATHS.any { File(it).exists() } }
    probe("root_apps") { ROOT_APPS.any { installed(pm, it) } }
    probe("writable_system") { systemMountedWritable() }
    probe("frida") { fridaMapped() || loopbackPortOpen(FRIDA_PORT) }
    probe("debugger") { Debug.isDebuggerConnected() || Debug.waitingForDebugger() }

    return mapOf(
      "rooted" to signals.any { it in ROOT_TOKENS },
      "hooked" to signals.any { it in HOOK_TOKENS },
      "signals" to signals,
    )
  }

  @Suppress("DEPRECATION")
  private fun installed(pm: PackageManager, pkg: String): Boolean = try {
    pm.getPackageInfo(pkg, 0)
    true
  } catch (_: PackageManager.NameNotFoundException) {
    false
  }

  /** A system partition mounted read-write (`/proc/mounts`, option field). */
  private fun systemMountedWritable(): Boolean =
    File("/proc/mounts").readLines().any { line ->
      val fields = line.split(" ")
      fields.size >= 4 && fields[1] in SYSTEM_MOUNTS &&
        fields[3].split(",").contains("rw")
    }

  /** Frida's agent or gadget mapped into this process. */
  private fun fridaMapped(): Boolean =
    File("/proc/self/maps").useLines { lines ->
      lines.any { it.contains("frida", ignoreCase = true) || it.contains("gum-js-loop") }
    }

  /** frida-server's default port answering on loopback. */
  private fun loopbackPortOpen(port: Int): Boolean = try {
    Socket().use { it.connect(InetSocketAddress("127.0.0.1", port), 200); true }
  } catch (_: Throwable) {
    false
  }
}
