import Foundation
import Security

/// TLS delegate for homelab access.
///
/// - For direct LAN IP connections (192.168.x.x etc.), we relax hostname verification
///   because the Let's Encrypt cert is issued for the domain name, not the IP.
///   We still require the certificate *chain* to be valid (not arbitrary self-signed).
///
/// - For the public domain name, we always use the system's default validation + SNI.
///
/// This is a pragmatic compromise for a private homelab. Do NOT use in production
/// internet-facing services without proper certificate pinning.
final class HomelabTLSDelegate: NSObject, URLSessionDelegate {
    static let shared = HomelabTLSDelegate()

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
        // All other hosts (domain, WAN IP) go through normal validation.
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

        if isLanIP {
            // Validate that the certificate chain itself is valid (trusted root, not expired, etc.)
            // but ignore hostname mismatch (expected when connecting by IP).
            var error: CFError?
            if SecTrustEvaluateWithError(trust, &error) {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            } else {
                // Chain validation failed — fall back to default (will likely reject)
                NSLog("HomelabTLS: chain validation failed for LAN IP %@ - %@", host, (error as Error?)?.localizedDescription ?? "unknown")
            }
        }

        // Default path for domain name and everything else.
        completionHandler(.performDefaultHandling, nil)
    }
}