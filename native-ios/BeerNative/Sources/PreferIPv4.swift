import Foundation
import Darwin

/// Miroir exact d'Android `preferIpv4Dns` (OkHttp Dns).
/// OkHttp : lookup → IPv4 d'abord → socket sur v4, URL reste le hostname côté app.
/// iOS URLSession ne permet pas un Dns custom : on résout l'A puis on dial l'IPv4
/// (URL en littéral + Host/SNI gérés comme l'interceptor Android WAN_IPV4).
enum PreferIPv4 {
    /// Comme Android : v4 d'abord, puis le reste (si besoin).
    static func lookup(_ hostname: String) -> [String] {
        if let lit = literalIPv4(hostname) { return [lit] }

        let v4 = resolve(hostname, family: AF_INET)
        let v6 = resolve(hostname, family: AF_INET6)
        if v4.isEmpty { return v6 }
        return v4 + v6
    }

    /// Première IPv4 (enregistrement A), sinon nil.
    static func firstIPv4(_ hostname: String) -> String? {
        if let lit = literalIPv4(hostname) { return lit }
        return resolve(hostname, family: AF_INET).first
    }

    /// Android PreferIpv4Dns + interceptor Host sur IP WAN.
    /// Réécrit `eiter.freeboxos.fr` → `https://<A>/…` + header Host canonique.
    static func applyToRequest(_ request: inout URLRequest) {
        guard let url = request.url, var host = url.host, !host.isEmpty else { return }

        // Déjà en IP WAN : Host comme Android interceptor
        if host == ServerSettings.wanIPv4 {
            request.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
            return
        }

        // FQDN public uniquement (pas le LAN :8444)
        guard host == ServerSettings.canonicalHost else { return }

        let ip = firstIPv4(host) ?? ServerSettings.wanIPv4
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        c.host = ip
        c.scheme = "https"
        // 443 implicite
        if c.port == 443 { c.port = nil }
        guard let fixed = c.url else { return }
        request.url = fixed
        request.setValue(ServerSettings.canonicalHost, forHTTPHeaderField: "Host")
        NSLog("PreferIPv4: %@ → %@ (Host=%@)", host, ip, ServerSettings.canonicalHost)
    }

    // MARK: - private

    private static func literalIPv4(_ s: String) -> String? {
        var addr = in_addr()
        if s.withCString({ inet_pton(AF_INET, $0, &addr) }) == 1 {
            return s
        }
        return nil
    }

    private static func resolve(_ hostname: String, family: Int32) -> [String] {
        var hints = addrinfo(
            ai_flags: 0, // pas AI_ADDRCONFIG (peut masquer l'A en 5G dual-stack)
            ai_family: family,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let rc = getaddrinfo(hostname, "443", &hints, &result)
        guard rc == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }

        var out: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let info = ptr {
            var hostbuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                info.pointee.ai_addr,
                info.pointee.ai_addrlen,
                &hostbuf,
                socklen_t(hostbuf.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 {
                let s = String(cString: hostbuf)
                if !out.contains(s) { out.append(s) }
            }
            ptr = info.pointee.ai_next
        }
        return out
    }
}
