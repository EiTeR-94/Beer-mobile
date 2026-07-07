import Foundation

/// Session locale — permet l'accès HL après au moins une connexion réussie.
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