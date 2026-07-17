import Foundation
import Darwin

/// Miroir d'Android `preferIpv4Dns` pour URLSession (pas de Dns custom iOS).
/// OkHttp : URL FQDN + socket sur l'A. Ici : on réécrit l'URL en IPv4 pour le dial,
/// Host = FQDN (interceptor Android), HomelabTLS accepte le cert domaine sur l'IP.
enum PreferIPv4 {
    static func firstIPv4(_ hostname: String) -> String? {
        if isIPv4Literal(hostname) { return hostname }
        return resolveA(hostname).first
    }

    /// Applique preferIpv4Dns + Host interceptor Android sur la requête.
    static func applyAndroidStyle(_ request: inout URLRequest) {
        guard let url = request.url, let host = url.host, !host.isEmpty else { return }

        // Déjà en IP littérale : Host = FQDN (comme OkHttp interceptor WAN_IPV4)
        if isIPv4Literal(host) {
            request.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
            return
        }

        // FQDN public → dial l'enregistrement A (jamais AAAA)
        guard host == ServerSettings.canonicalHost else { return }
        let ip = firstIPv4(host) ?? ServerSettings.wanIPv4
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        c.host = ip
        c.scheme = "https"
        if c.port == 443 { c.port = nil }
        guard let fixed = c.url else { return }
        request.url = fixed
        request.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
        NSLog("PreferIPv4: %@ → %@ (Host=%@)", host, ip, ServerSettings.canonicalHost)
    }

    private static func isIPv4Literal(_ s: String) -> Bool {
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
