package co.myazahq.kyc

import android.content.Context
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest

/**
 * Play Integrity, Standard API, for `fingerprint.attestation` on Android
 * (kyc-core docs/DEVICE_INTEL_WIRE.md §2).
 *
 * The token provider is prepared ONCE per process (that warm-up is the slow
 * part) and reused for every request; a failed request drops it so the next
 * one prepares afresh. The requestHash is the lowercase hex SHA-256 of the
 * server's challenge, computed in Dart. Without Play services, or before the
 * host links its app to the Cloud project in Play Console, the tasks fail and
 * [token] answers null: the submission simply goes out without an attestation.
 *
 * Called on the main thread; the Task callbacks also land there.
 */
class PlayIntegrity(private val context: Context) {
  private var manager: StandardIntegrityManager? = null
  private var provider: StandardIntegrityTokenProvider? = null
  private var preparedFor: Long? = null

  fun token(cloudProjectNumber: Long, requestHash: String, done: (String?) -> Unit) {
    try {
      val ready = provider
      if (ready != null && preparedFor == cloudProjectNumber) {
        request(ready, requestHash, done)
        return
      }
      val mgr = manager ?: IntegrityManagerFactory.createStandard(context).also { manager = it }
      mgr.prepareIntegrityToken(
        PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(cloudProjectNumber).build(),
      )
        .addOnSuccessListener { prepared ->
          provider = prepared
          preparedFor = cloudProjectNumber
          request(prepared, requestHash, done)
        }
        .addOnFailureListener { done(null) }
    } catch (_: Throwable) {
      done(null)
    }
  }

  private fun request(p: StandardIntegrityTokenProvider, hash: String, done: (String?) -> Unit) {
    p.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
      .addOnSuccessListener { done(it.token()) }
      .addOnFailureListener {
        // An expired or invalidated provider: prepare again next time.
        provider = null
        preparedFor = null
        done(null)
      }
  }
}
