import Foundation
import Security
import Darwin

/// Miroir d'Android `HomelabTls.kt` :
/// - chaîne Let's Encrypt valide (comme TrustManager.checkServerTrusted)
/// - si host = IP LAN/WAN : hostname OK si le cert est pour `eiter.freeboxos.fr`
///   (comme HostnameVerifier qui re-vérifie PIN_DOMAIN)
///
/// Critique PreferIPv4 : URL = `https://82.64…/` → protectionSpace.host = IP
/// → éval SSL standard échoue (SAN ≠ IP) → sans ce délégué = « Connexion sécurisée impossible ».
final class HomelabTLSDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = HomelabTLSDelegate()
    private let pinDomain = ServerSettings.canonicalHost

    // Session-level
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    // Task-level (souvent utilisé par data(for:) async)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    private func handle(
        _ challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host
        let isIP = ServerSettings.isLanHost(host) || host == ServerSettings.wanIPv4 || isIPv4Literal(host)

        var error: CFError?

        // 1) Domaine canonique : éval système
        if !isIP, SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // 2) IP (PreferIPv4 / LAN) — comme Android HostnameVerifier(PIN_DOMAIN)
        if isIP {
            // 2a) Policy SSL sur le FQDN (pas sur l'IP)
            let sslDomain = SecPolicyCreateSSL(true, pinDomain as CFString)
            SecTrustSetPolicies(trust, sslDomain)
            error = nil
            if SecTrustEvaluateWithError(trust, &error) {
                NSLog("HomelabTLS: OK IP %@ via SSL policy %@", host, pinDomain)
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }

            // 2b) Chaîne X.509 seule + SAN contient le FQDN (TrustManager + verify domain)
            let basic = SecPolicyCreateBasicX509()
            SecTrustSetPolicies(trust, basic)
            error = nil
            if SecTrustEvaluateWithError(trust, &error), leafMatchesDomain(trust, domain: pinDomain) {
                NSLog("HomelabTLS: OK IP %@ via chain+SAN %@", host, pinDomain)
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            NSLog(
                "HomelabTLS: FAIL IP %@ domain=%@ err=%@",
                host,
                pinDomain,
                String(describing: error)
            )
        } else {
            // FQDN mais éval initiale ratée : un essai de plus
            error = nil
            if SecTrustEvaluateWithError(trust, &error) {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            NSLog("HomelabTLS: FAIL host %@ err=%@", host, String(describing: error))
        }

        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private func isIPv4Literal(_ s: String) -> Bool {
        var addr = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &addr) } == 1
    }

    /// Leaf cert DNS SAN / CN contient le domaine pin.
    private func leafMatchesDomain(_ trust: SecTrust, domain: String) -> Bool {
        if let cfArr = SecTrustCopyCertificateChain(trust) {
            let n = CFArrayGetCount(cfArr)
            if n > 0 {
                let raw = CFArrayGetValueAtIndex(cfArr, 0)
                let cert = unsafeBitCast(raw, to: SecCertificate.self)
                return certSummaryMatches(cert, domain: domain)
            }
        }
        return false
    }

    private func certSummaryMatches(_ cert: SecCertificate, domain: String) -> Bool {
        // CN (souvent "eiter.freeboxos.fr")
        if let summary = SecCertificateCopySubjectSummary(cert) as String?,
           summary.localizedCaseInsensitiveContains(domain) {
            return true
        }
        // SAN LE : le FQDN est en clair dans le DER
        let data = SecCertificateCopyData(cert) as Data
        if let needle = domain.data(using: .utf8), data.range(of: needle) != nil {
            return true
        }
        return false
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
