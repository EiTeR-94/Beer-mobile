import Foundation

/// Custom URLProtocol that forces IPv4 connections to the canonical domain on port 443.
///
/// Reason: The Freebox AAAA (IPv6) record for eiter.freeboxos.fr is currently unreachable
/// (points to the router). We force IPv4 + correct SNI to avoid SSL issues.
/// 
/// Used for owner LAN/VPN access (prefers direct IP, falls back to domain if needed).
///
/// By intercepting and delegating to HomelabIPv4Transport (IPv4 + correct SNI),
/// we bypass the broken AAAA. Registered on the relevant URLSession configs.
final class PlexiIPv4URLProtocol: URLProtocol {
    static var useCustomTransport = true  // false on trusted local wifi/VPN to use high-level URLSession

    private var loadTask: Task<Void, Never>?
    private static let handledKey = "PlexiIPv4URLProtocolHandled"

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        if property(forKey: handledKey, in: request) != nil { return false }
        if !useCustomTransport { return false } // on trusted local, use high-level URLSession directly
        let port = url.port ?? 443
        return url.scheme == "https"
            && url.host == ServerSettings.canonicalHost
            && port == 443
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        guard let mutable = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            return request
        }
        URLProtocol.setProperty(true, forKey: handledKey, in: mutable)
        return mutable as URLRequest
    }

    override func startLoading() {
        loadTask = Task {
            do {
                let (data, response, _) = try await HomelabIPv4Transport.perform(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                // Toujours produire une erreur avec description claire pour éviter "erreur 0" générique
                let desc = "Erreur transport: \(error.localizedDescription)" // slow link or first connect on VPN/WiFi
                let urlErr = URLError(.unknown, userInfo: [NSLocalizedDescriptionKey: desc])
                client?.urlProtocol(self, didFailWithError: urlErr)
            }
        }
    }

    override func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}