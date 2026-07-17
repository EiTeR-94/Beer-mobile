import Foundation
import Darwin

/// Miroir d'Android `preferIpv4Dns` — **uniquement** la résolution DNS.
/// Le dial est dans `AndroidOkHttpClient` (comme OkHttp socket après Dns.lookup).
enum PreferIPv4 {
    /// Liste A puis AAAA (Android: v4 + non-v4).
    static func lookup(_ hostname: String) -> [String] {
        if isIPv4Literal(hostname) { return [hostname] }
        let v4 = resolve(hostname, family: AF_INET)
        let v6 = resolve(hostname, family: AF_INET6)
        if v4.isEmpty { return v6 }
        return v4 + v6
    }

    static func firstIPv4(_ hostname: String) -> String? {
        if isIPv4Literal(hostname) { return hostname }
        return resolve(hostname, family: AF_INET).first
    }

    private static func isIPv4Literal(_ s: String) -> Bool {
        var a = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &a) } == 1
    }

    private static func resolve(_ hostname: String, family: Int32) -> [String] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: family,
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
