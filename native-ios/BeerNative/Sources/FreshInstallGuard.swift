import Foundation

/// iOS : le **Keychain survit à la désinstallation** de l’app (comportement Apple).
/// UserDefaults est effacé. Si on relance sans marqueur UD, on purge Keychain + sessions
/// pour ne pas ré-hériter d’un Bearer invité d’une install précédente.
enum FreshInstallGuard {
    private static let markerKey = "plexibeer_install_marker_v1"

    /// À appeler tout au début du lancement (avant bootstrap).
    static func runIfNeeded() {
        let ud = UserDefaults.standard
        if ud.bool(forKey: markerKey) {
            return
        }
        // Première ouverture de cette installation (UD vide = reinstall ou 1er install)
        NSLog("FreshInstallGuard: new install — wiping Keychain invite/session leftovers")
        InviteSessionStore.wipeAllIncludingDevice()
        BeerSessionStore.clear()
        // Cookies HTTP (parfois en Keychain aussi selon versions)
        if let cookies = HTTPCookieStorage.shared.cookies {
            cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
        // Username keychain legacy
        KeychainStore.username = nil
        ud.set(true, forKey: markerKey)
    }
}
