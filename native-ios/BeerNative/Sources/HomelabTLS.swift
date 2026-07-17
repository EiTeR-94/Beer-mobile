import Foundation
import Security
import Darwin

/// Trust pour dial IP (PreferIPv4) avec cert LE de `eiter.freeboxos.fr`.
/// Miroir Android HostnameVerifier(PIN_DOMAIN).
final class HomelabTLSDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    static let shared = HomelabTLSDelegate()
    private let pinDomain = ServerSettings.canonicalHost

    /// Task-level uniquement (évite double completion session+task → SSL foireux).
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge, completionHandler: completionHandler)
    }

    /// Fallback si pas de task challenge (certaines configs session).
    func urlSession(
        _ session: URLSession,
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
        let isIP = ServerSettings.isLanHost(host)
            || host == ServerSettings.wanIPv4
            || isIPv4Literal(host)

        if isIP {
            if evaluateForPinnedDomain(trust) {
                NSLog("HomelabTLS: accept IP %@ as %@", host, pinDomain)
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                NSLog("HomelabTLS: reject IP %@", host)
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
            return
        }

        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        let policy = SecPolicyCreateSSL(true, pinDomain as CFString)
        SecTrustSetPolicies(trust, policy)
        error = nil
        if SecTrustEvaluateWithError(trust, &error) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        NSLog("HomelabTLS: reject host %@", host)
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    private func evaluateForPinnedDomain(_ trust: SecTrust) -> Bool {
        var error: CFError?

        // 1) SSL policy for FQDN (dial was IP)
        let ssl = SecPolicyCreateSSL(true, pinDomain as CFString)
        SecTrustSetPolicies(trust, ssl)
        if SecTrustEvaluateWithError(trust, &error) {
            return true
        }

        // 2) Basic chain + leaf SAN/CN contains domain
        let basic = SecPolicyCreateBasicX509()
        SecTrustSetPolicies(trust, basic)
        error = nil
        if SecTrustEvaluateWithError(trust, &error), leafMatchesDomain(trust) {
            return true
        }

        // 3) Leaf is clearly our cert — accept (URLSession SNI=IP casse souvent l'éval stricte)
        if leafMatchesDomain(trust) {
            NSLog("HomelabTLS: leaf SAN match — accept %@", pinDomain)
            return true
        }
        return false
    }

    private func isIPv4Literal(_ s: String) -> Bool {
        var addr = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &addr) } == 1
    }

    private func leafMatchesDomain(_ trust: SecTrust) -> Bool {
        if let cfArr = SecTrustCopyCertificateChain(trust) {
            let n = CFArrayGetCount(cfArr)
            if n > 0 {
                let cert = unsafeBitCast(CFArrayGetValueAtIndex(cfArr, 0), to: SecCertificate.self)
                return certContainsDomain(cert)
            }
        }
        return false
    }

    private func certContainsDomain(_ cert: SecCertificate) -> Bool {
        if let summary = SecCertificateCopySubjectSummary(cert) as String?,
           summary.localizedCaseInsensitiveContains(pinDomain) {
            return true
        }
        let data = SecCertificateCopyData(cert) as Data
        if let needle = pinDomain.data(using: .utf8), data.range(of: needle) != nil {
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
