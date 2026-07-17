import Foundation

/// Optionnel — non enregistré sur le client invite principal.
/// Si utilisé : même transport HomelabIPv4 qu'en 3.7.0.
final class PlexiIPv4URLProtocol: URLProtocol {
    static var useCustomTransport = false
    private var loadTask: Task<Void, Never>?
    private static let handledKey = "PlexiIPv4URLProtocolHandled"

    override class func canInit(with request: URLRequest) -> Bool {
        guard let url = request.url else { return false }
        if property(forKey: handledKey, in: request) != nil { return false }
        if !useCustomTransport { return false }
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
                let desc = "Erreur transport: \(error.localizedDescription)"
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
