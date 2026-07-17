import Foundation
import Darwin

/// Miroir d'Android `preferIpv4Dns` pour URLSession.
///
/// Freebox : AAAA de `eiter.freeboxos.fr` est morte sur :443 → Happy Eyeballs iOS
/// tape IPv6 et échoue (SSL/timeout) de façon **aléatoire**.
///
/// Fix déterministe : dial **toujours** l'IPv4 WAN connue (`82.64.151.113`),
/// Host HTTP = FQDN (nginx). HomelabTLS accepte le cert LE du domaine sur l'IP.
enum PreferIPv4 {
    /// IPv4 WAN canonique (même IP qu'Android résout en A).
    static var wanIPv4: String { ServerSettings.wanIPv4 }

    static func firstIPv4(_ hostname: String) -> String? {
        if isIPv4Literal(hostname) { return hostname }
        // Préférer l'IP hardcodée pour le host canonique (pas de DNS flaky en 5G)
        if hostname == ServerSettings.canonicalHost {
            return wanIPv4
        }
        return resolveA(hostname).first ?? (hostname == ServerSettings.canonicalHost ? wanIPv4 : nil)
    }

    /// Force dial IPv4 + Host FQDN (équivalent OkHttp interceptor WAN).
    static func applyAndroidStyle(_ request: inout URLRequest) {
        guard let url = request.url, let host = url.host, !host.isEmpty else { return }

        if isIPv4Literal(host) {
            // Déjà en IP : Host = FQDN pour nginx
            request.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
            return
        }

        // FQDN public (ou tout host invite) → dial IPv4 hardcodée, jamais AAAA
        let ip = (host == ServerSettings.canonicalHost)
            ? wanIPv4
            : (firstIPv4(host) ?? wanIPv4)

        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        c.host = ip
        c.scheme = "https"
        if c.port == 443 { c.port = nil }
        guard let fixed = c.url else { return }
        request.url = fixed
        request.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
        NSLog("PreferIPv4: %@ → %@ (Host=%@)", host, ip, ServerSettings.canonicalHost)
    }

    static func isIPv4Literal(_ s: String) -> Bool {
        var a = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &a) } == 1
    }

    private static func resolveA(_ hostname: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, "443", &hints, &result) == 0, let first = result else {
            return []
        }
        defer { freeaddrinfo(first) }
        var out: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let info = ptr {
            var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                info.pointee.ai_addr,
                info.pointee.ai_addrlen,
                &buf,
                socklen_t(buf.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let s = String(cString: buf)
                if !out.contains(s) { out.append(s) }
            }
            ptr = info.pointee.ai_next
        }
        return out
    }
}
