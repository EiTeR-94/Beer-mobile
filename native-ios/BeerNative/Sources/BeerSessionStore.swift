import Foundation

/// Lightweight session flags stored in UserDefaults.
///
/// Used only for quick offline restore of "who am I" (username + role) and to decide
/// whether we can show cached UI when the server is unreachable.
/// Sensitive tokens are stored in Keychain (see KeychainStore). Guest system removed.
///
/// This mix is intentional: UserDefaults is fast and survives app restarts for UX,
/// while tokens stay protected.
enum BeerSessionStore {
    private static let ud = UserDefaults.standard

    static func save(user: String, isAdmin: Bool, isInvite: Bool) {
        ud.set(user, forKey: "beer_user")
        ud.set(isAdmin, forKey: "beer_is_admin")
        ud.set(isInvite, forKey: "beer_is_invite")
        ud.set(true, forKey: "beer_has_session")
    }

    static func restore() -> (user: String, isAdmin: Bool, isInvite: Bool)? {
        guard ud.bool(forKey: "beer_has_session"),
              let user = ud.string(forKey: "beer_user"), !user.isEmpty else { return nil }
        return (user, ud.bool(forKey: "beer_is_admin"), ud.bool(forKey: "beer_is_invite"))
    }

    static func clear() {
        ud.removeObject(forKey: "beer_user")
        ud.removeObject(forKey: "beer_is_admin")
        ud.removeObject(forKey: "beer_is_invite")
        ud.removeObject(forKey: "beer_has_session")
    }
}