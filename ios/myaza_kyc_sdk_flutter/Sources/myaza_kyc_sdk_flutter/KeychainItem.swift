import Foundation
import Security

/// A tiny generic-password store for Device Intelligence's two Keychain items
/// (service `co.myazahq.kyc`): `device-stable-id` and `app-attest-key-id`.
///
/// Keychain items survive an uninstall and reinstall, which is the point of
/// the stable id. Both are `AfterFirstUnlockThisDeviceOnly` and NOT
/// synchronizable, so they never leave this device through iCloud.
enum KeychainItem {
  static let service = "co.myazahq.kyc"

  private static func base(_ account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
  }

  static func read(_ account: String) -> String? {
    var query = base(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var out: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
      let data = out as? Data, let value = String(data: data, encoding: .utf8),
      !value.isEmpty
    else { return nil }
    return value
  }

  /// Replaces any existing value. Returns whether it was stored.
  @discardableResult
  static func write(_ account: String, _ value: String) -> Bool {
    delete(account)
    var item = base(account)
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
  }

  static func delete(_ account: String) {
    SecItemDelete(base(account) as CFDictionary)
  }
}
