import Foundation
import Security

/// Token Bearer invité passkey (session v2) — Keychain, indépendant des cookies admin.
enum PasskeySessionStore {
    private static let service = "fr.eiter.plexibeer"
    private static let account = "passkey_session_v2"

    static var accessToken: String? {
        get {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
                  let data = item as? Data,
                  let value = String(data: data, encoding: .utf8),
                  !value.isEmpty else { return nil }
            return value
        }
        set {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
            guard let value = newValue, let data = value.data(using: .utf8) else { return }
            let add: [String: Any] = query.merging([
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func save(accessToken: String) {
        self.accessToken = accessToken
    }

    static func clear() {
        accessToken = nil
    }
}