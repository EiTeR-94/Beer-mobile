import Foundation
import Security
import CommonCrypto

/// TLS delegate for homelab access.
///
/// - For direct LAN IP connections (192.168.x.x etc.), we relax hostname verification
///   because the Let's Encrypt cert is issued for the domain name, not the IP.
///   We still require the certificate *chain* to be valid (not arbitrary self-signed).
///
/// - For the public domain name, we always use the system's default validation + SNI + public key pinning.
///
/// This is a pragmatic compromise for a private homelab. Do NOT use in production
/// internet-facing services without proper certificate pinning.
/// Fix for "SSL refusé sur 192.168.1.50" - domain policy for IP connections (2026-07-07)
final class HomelabTLSDelegate: NSObject, URLSessionDelegate {
    static let shared = HomelabTLSDelegate()

    // Current SPKI SHA256 hash of the leaf cert public key for eiter.freeboxos.fr
    // Update after cert renewal if pinning starts failing.
    private let pinnedSPKIHashes: Set<String> = [
        "QfgyToNrrLTsFusj/VsUM9hl4l+EUw2FstVeDDV3HCM="
    ]

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

        // Only relax hostname check for private LAN IPs.
        // All other hosts (domain, WAN IP) go through normal validation + pinning.
        let isLanIP = host.hasPrefix("192.168.") ||
                      host.hasPrefix("10.") ||
                      host.hasPrefix("172.16.") || host.hasPrefix("172.17.") ||
                      host.hasPrefix("172.18.") || host.hasPrefix("172.19.") ||
                      host.hasPrefix("172.20.") || host.hasPrefix("172.21.") ||
                      host.hasPrefix("172.22.") || host.hasPrefix("172.23.") ||
                      host.hasPrefix("172.24.") || host.hasPrefix("172.25.") ||
                      host.hasPrefix("172.26.") || host.hasPrefix("172.27.") ||
                      host.hasPrefix("172.28.") || host.hasPrefix("172.29.") ||
                      host.hasPrefix("172.30.") || host.hasPrefix("172.31.")

        // Try normal evaluation first (works for domain name connections)
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            if !isLanIP && !isPinned(trust: trust) {
                NSLog("HomelabTLS: pinning failed for %@", host)
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // If normal eval failed and this is a LAN IP, retry with a policy that
        // validates the certificate against the real domain name (eiter.freeboxos.fr).
        // This is required because the LE cert's SAN matches the domain, not the IP address.
        if isLanIP {
            let domain = "eiter.freeboxos.fr" as CFString
            let policy = SecPolicyCreateSSL(true, domain)
            SecTrustSetPolicies(trust, [policy] as CFArray)

            if SecTrustEvaluateWithError(trust, &error) {
                NSLog("HomelabTLS: accepted LAN IP %@ using domain policy", host)
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            } else {
                NSLog("HomelabTLS: domain policy validation failed for LAN IP %@ - %@", host, (error as Error?)?.localizedDescription ?? "unknown")
            }
        }

        // Default path for domain name and everything else (or failed LAN).
        completionHandler(.performDefaultHandling, nil)
    }

    private func isPinned(trust: SecTrust) -> Bool {
        guard let cert = SecTrustGetCertificateAtIndex(trust, 0) else { return false }
        var secTrust: SecTrust?
        let policy = SecPolicyCreateBasicX509()
        guard SecTrustCreateWithCertificates(cert, policy, &secTrust) == errSecSuccess,
              let t = secTrust,
              let publicKey = SecTrustCopyPublicKey(t) else { return false }

        var error: Unmanaged<CFError>?
        guard let keyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else { return false }

        let hash = keyData.sha256().base64EncodedString()
        return pinnedSPKIHashes.contains(hash)
    }
}

private extension Data {
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
}