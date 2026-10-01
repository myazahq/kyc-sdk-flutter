import DeviceCheck
import Foundation

/// App Attest for `fingerprint.attestation` on iOS
/// (kyc-core docs/DEVICE_INTEL_WIRE.md §2).
///
/// ONE key per install; its keyId lives in the Keychain (account
/// `app-attest-key-id`) so it outlives the process. The server decides, per
/// challenge, whether it wants a fresh attestation (no key yet, or a key it
/// does not know) or an assertion from the key it already trusts. The
/// clientDataHash (SHA-256 of the challenge) is computed in Dart.
///
/// The host app needs the App Attest capability
/// (`com.apple.developer.devicecheck.appattest-environment`); without it key
/// generation fails and the submission goes out without an attestation.
/// Simulators and iOS 13 report unsupported. Every failure completes with nil.
enum AppAttest {
  static let account = "app-attest-key-id"

  /// `{ supported, keyId? }`.
  static func state() -> [String: Any] {
    if #available(iOS 14.0, *), DCAppAttestService.shared.isSupported {
      return ["supported": true, "keyId": KeychainItem.read(account).map { $0 as Any } ?? NSNull()]
    }
    return ["supported": false]
  }

  /// Completes with `{ keyId, attestation }` or `{ keyId, assertion }`
  /// (base64), or nil. Completion may arrive on any queue.
  static func run(
    keyId: String?, clientDataHash: Data, attest: Bool,
    done: @escaping ([String: Any]?) -> Void
  ) {
    guard #available(iOS 14.0, *), DCAppAttestService.shared.isSupported else {
      done(nil)
      return
    }
    if attest {
      attestKey(existing: keyId, clientDataHash: clientDataHash, done: done)
      return
    }
    guard let keyId else {
      done(nil)
      return
    }
    DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash) {
      assertion, error in
      guard let assertion, error == nil else {
        // A key the device no longer holds can never assert again: forget it,
        // so the next submission attests a fresh one.
        if (error as? DCError)?.code == .invalidKey { KeychainItem.delete(account) }
        done(nil)
        return
      }
      done(["keyId": keyId, "assertion": assertion.base64EncodedString()])
    }
  }

  /// Attests the stored key, or a freshly generated one when there is none or
  /// the stored one cannot be attested (a key attests once).
  @available(iOS 14.0, *)
  private static func attestKey(
    existing: String?, clientDataHash: Data, done: @escaping ([String: Any]?) -> Void
  ) {
    let service = DCAppAttestService.shared
    func attest(_ keyId: String, retryWithNewKey: Bool) {
      service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
        if let attestation, error == nil {
          done(["keyId": keyId, "attestation": attestation.base64EncodedString()])
        } else if retryWithNewKey {
          generate()
        } else {
          done(nil)
        }
      }
    }
    func generate() {
      service.generateKey { keyId, error in
        guard let keyId, error == nil, KeychainItem.write(account, keyId) else {
          done(nil)
          return
        }
        attest(keyId, retryWithNewKey: false)
      }
    }
    if let existing { attest(existing, retryWithNewKey: true) } else { generate() }
  }
}
