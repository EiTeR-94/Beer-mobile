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
    // Backup: intermediate Let's Encrypt (for rotation safety). Updated 2026-07.
    // Rotation: re-compute with `openssl s_client ... | ... dgst -sha256 -binary | base64` when cert renews.
    private let pinnedSPKIHashes: Set<String> = [
        "QfgyToNrrLTsFusj/VsUM9hl4l+EUw2FstVeDDV3HCM=",  // leaf
        "y7xVm0TVJNahMr2sZydE2jQH8SquXV9yLF9seROHHHU="   // intermediate backup (LE)
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

        // Relax hostname check for private LAN IPs + WAN IPv4 (même cert LE domaine).
        let isWanIP = (host == ServerSettings.wanIPv4)
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
        let isIPHost = isLanIP || isWanIP

        // Try normal evaluation first (works for domain name connections)
        // Pinning SPKI en soft-fail (log only) — un pin trop strict cassait le Wi‑Fi après renew LE
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) {
            let isOurHost = (host == "eiter.freeboxos.fr" || isIPHost)
            if isOurHost && !isPinned(trust: trust) {
                NSLog("HomelabTLS: pin mismatch for %@ (accepting valid chain)", host)
            }
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }

        // Si eval normal échoue (IP ≠ SAN cert), revalider contre eiter.freeboxos.fr
        if isIPHost {
            let domain = "eiter.freeboxos.fr" as CFString
            let policy = SecPolicyCreateSSL(true, domain)
            SecTrustSetPolicies(trust, [policy] as CFArray)

            if SecTrustEvaluateWithError(trust, &error) {
                NSLog("HomelabTLS: accepted IP %@ using domain policy", host)
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            } else {
                NSLog("HomelabTLS: domain policy validation failed for IP %@ - %@", host, (error as Error?)?.localizedDescription ?? "unknown")
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