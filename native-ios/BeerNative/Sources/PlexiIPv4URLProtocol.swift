import Foundation

/// Invités 5G : URLSession + cookies système (comme PWA), TCP forcé en IPv4 (AAAA Freebox morte).
/// URLSession pose/relit les cookies ; ce protocol ne fait que le transport IPv4+SNI.
final class PlexiIPv4URLProtocol: URLProtocol {
    private var loadTask: Task<Void, Never>?
    private static let handledKey = "PlexiIPv4URLProtocolHandled"

    static var isEnabled = false

    override class func canInit(with request: URLRequest) -> Bool {
        guard isEnabled, let url = request.url else { return false }
        if property(forKey: handledKey, in: request) != nil { return false }
        return url.scheme == "https" && url.host == ServerSettings.canonicalHost
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
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}