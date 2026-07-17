import Foundation
import Security

/// Miroir exact d'Android `HomelabTls.kt` :
/// - chaîne LE valide obligatoire
/// - LAN IP / WAN IP : hostname OK si cert valide pour eiter.freeboxos.fr
/// - PAS de pin SPKI qui tue la connexion
final class HomelabTLSDelegate: NSObject, URLSessionDelegate {
    static let shared = HomelabTLSDelegate()
    private let pinDomain = ServerSettings.canonicalHost

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let isLan = ServerSettings.isLanHost(host)
        let isWanIP = (host == ServerSettings.wanIPv4)

        // 1) Éval normale (domaine)
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // 2) IP LAN ou WAN publique : policy SSL sur le domaine (comme Android HostnameVerifier)
        if isLan || isWanIP {
            let policy = SecPolicyCreateSSL(true, pinDomain as CFString)
            SecTrustSetPolicies(trust, [policy] as CFArray)
            if SecTrustEvaluateWithError(trust, &error) {
                NSLog("HomelabTLS: accepted IP %@ via domain %@", host, pinDomain)
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            NSLog("HomelabTLS: domain policy failed for %@: %@", host, String(describing: error))
        }

        completionHandler(.cancelAuthenticationChallenge, nil)
    }
}

extension ServerSettings {
    static func isLanHost(_ host: String) -> Bool {
        if host.hasPrefix("192.168.") { return true }
        if host.hasPrefix("10.") { return true }
        if host.hasPrefix("172.") {
            let parts = host.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }
}
