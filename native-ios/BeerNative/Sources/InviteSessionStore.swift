import Foundation
import Security

/// Session invité iOS — Bearer device-bound (WAN 4G/5G), miroir Android InviteSessionStore.
enum InviteSessionStore {
    private static let service = "fr.eiter.plexibeer.invite"
    private static let keyToken = "access_token"
    private static let keyDevice = "device_id"
    private static let keyUser = "user"
    private static let keyLabel = "label"
    private static let keyExpires = "expires_at"
    private static let keyActive = "active"

    private static let ud = UserDefaults.standard

    static var hasInviteSession: Bool {
        ud.bool(forKey: keyActive) && !(accessToken ?? "").isEmpty
    }

    static var accessToken: String? {
        get { keychainGet(keyToken) }
        set {
            keychainSet(keyToken, newValue)
            ud.set(newValue != nil && !(newValue ?? "").isEmpty, forKey: keyActive)
        }
    }

    static var deviceId: String {
        if let existing = keychainGet(keyDevice), existing.count >= 16, existing.count <= 64 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let id = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let clipped = String(id.prefix(32))
        keychainSet(keyDevice, clipped)
        return clipped
    }

    static var username: String? {
        get { ud.string(forKey: keyUser) }
        set { ud.set(newValue, forKey: keyUser) }
    }

    static var label: String? {
        get { ud.string(forKey: keyLabel) }
        set { ud.set(newValue, forKey: keyLabel) }
    }

    static var expiresAt: String? {
        get { ud.string(forKey: keyExpires) }
        set { ud.set(newValue, forKey: keyExpires) }
    }

    static func save(accessToken: String, user: String, label: String?, expiresAt: String?, deviceId: String) {
        self.accessToken = accessToken
        keychainSet(keyDevice, deviceId)
        username = user
        self.label = label
        self.expiresAt = expiresAt
        ud.set(true, forKey: keyActive)
    }

    /// Efface le Bearer mais conserve device_id (rebind / réactivation).
    static func clear() {
        let kept = keychainGet(keyDevice)
        keychainSet(keyToken, nil)
        username = nil
        label = nil
        expiresAt = nil
        ud.set(false, forKey: keyActive)
        if let kept { keychainSet(keyDevice, kept) }
    }

    /// Extrait le token depuis une URL join ou un token brut.
    static func parseInviteToken(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let range = s.range(of: "/join/") {
            var after = String(s[range.upperBound...])
            if let q = after.firstIndex(of: "?") { after = String(after[..<q]) }
            if let h = after.firstIndex(of: "#") { after = String(after[..<h]) }
            if let slash = after.firstIndex(of: "/") { after = String(after[..<slash]) }
            let token = after.trimmingCharacters(in: .whitespacesAndNewlines)
            return isValidToken(token) ? token : nil
        }
        return isValidToken(s) ? s : nil
    }

    private static func isValidToken(_ t: String) -> Bool {
        guard t.count >= 24, t.count <= 64 else { return false }
        return t.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" }
    }

    private static func keychainGet(_ account: String) -> String? {
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

    private static func keychainSet(_ account: String, _ value: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        let add: [String: Any] = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]) { $1 }
        SecItemAdd(add as CFDictionary, nil)
    }
}
