import Foundation
import Darwin

/// Équivalent exact d'Android `preferIpv4Dns` (OkHttp Dns).
/// Résout d'abord les A (IPv4), puis le reste — évite AAAA Freebox mort en 5G.
enum PreferIPv4 {
    /// Liste d'adresses : IPv4 d'abord, comme Android.
    static func lookup(_ hostname: String) -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
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

        var v4: [String] = []
        var v6: [String] = []
        var ptr: UnsafeMutablePointer<addrinfo>? = first
        while let info = ptr {
            if info.pointee.ai_family == AF_INET {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    info.pointee.ai_addr,
                    info.pointee.ai_addrlen,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    v4.append(String(cString: host))
                }
            } else if info.pointee.ai_family == AF_INET6 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    info.pointee.ai_addr,
                    info.pointee.ai_addrlen,
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    v6.append(String(cString: host))
                }
            }
            ptr = info.pointee.ai_next
        }
        // Android: v4 + non-v4
        return v4 + v6
    }

    /// Première IPv4, sinon nil.
    static func firstIPv4(_ hostname: String) -> String? {
        lookup(hostname).first { !$0.contains(":") }
    }
}
