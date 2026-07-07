import Foundation

/// Custom URLProtocol that forces IPv4 connections to the canonical domain on port 443.
///
/// Reason: The Freebox AAAA (IPv6) record for eiter.freeboxos.fr is currently unreachable
/// (TCP conn refused on the router's ::1). iOS (esp. 5G/cellular) often prefers IPv6,
/// causing SSL/TLS failures ("SSL refusé").
/// 
/// Used for BOTH:
/// - LAN accounts (when they fall back to domain, though they prefer direct IP)
/// - 5G guest/passkey path (plain https://eiter... requests)
///
/// By intercepting and delegating to HomelabIPv4Transport (IPv4 + correct SNI),
/// we bypass the broken AAAA. Registered on the relevant URLSession configs.
final class PlexiIPv4URLProtocol: URLProtocol {
    private var loadTask: Task<Void, Never>?
    private static let handledKey = "PlexiIPv4URLProtocolHandled"

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        if property(forKey: handledKey, in: request) != nil { return false }
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
                let nsErr = NSError(domain: "fr.eiter.plexibeer", code: 0, userInfo: [
                    NSLocalizedDescriptionKey: "Erreur 5G (IPv4): \(error.localizedDescription)"
                ])
                client?.urlProtocol(self, didFailWithError: nsErr)
            }
        }
    }

    override func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}