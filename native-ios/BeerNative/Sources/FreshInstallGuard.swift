import Foundation

/// iOS : le **Keychain survit à la désinstallation** de l’app (comportement Apple).
/// UserDefaults est effacé. Si on relance sans marqueur UD, on purge les restes
/// d'INVITÉ (Bearer) d'une install précédente uniquement — jamais la session du
/// propriétaire (cookie beer_session), pour laquelle survivre à une réinstall est
/// voulu, pas un risque : un cookie d'invité périmé sur un appareil revendu est le
/// seul scénario visé par ce garde-fou.
///
/// 17/09/2026 : ce garde-fou effaçait TOUS les cookies (dont beer_session, dont
/// dépend AppModel.bootstrap() pour savoir si le propriétaire est connecté) à
/// chaque déclenchement — si le marqueur UserDefaults ne persistait pas de façon
/// fiable entre deux lancements (cause exacte non confirmée sans debug sur
/// l'appareil), ça forçait une reconnexion manuelle à chaque ouverture de l'app,
/// même avec une session serveur toujours valide. Restreint désormais au
/// périmètre invité, qui est le seul risque réel décrit ci-dessus.
enum FreshInstallGuard {
    private static let markerKey = "plexibeer_install_marker_v1"

    /// À appeler tout au début du lancement (avant bootstrap).
    static func runIfNeeded() {
        let ud = UserDefaults.standard
        if ud.bool(forKey: markerKey) {
            return
        }
        // Première ouverture de cette installation (UD vide = reinstall ou 1er install)
        NSLog("FreshInstallGuard: new install — wiping invite Keychain leftovers only")
        InviteSessionStore.wipeAllIncludingDevice()
        ud.set(true, forKey: markerKey)
    }
}
