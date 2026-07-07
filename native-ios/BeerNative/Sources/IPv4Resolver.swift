import Darwin
import Foundation

enum IPv4Resolver {
    static func resolve(_ hostname: String) -> String? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &result) == 0, let result else { return nil }
        defer { freeaddrinfo(result) }

        var addr = result.pointee.ai_addr.pointee
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        return withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sin in
                guard inet_ntop(AF_INET, &sin.pointee.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else {
                    return nil
                }
                return String(cString: buffer)
            }
        }
    }

    static func isIPv4(_ host: String) -> Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, host, &addr) == 1
    }
}