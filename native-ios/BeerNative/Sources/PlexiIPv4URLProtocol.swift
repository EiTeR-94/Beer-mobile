import Foundation

/// Force IPv4 pour eiter.freeboxos.fr:443 — AAAA Freebox morte (sinon SSL refusé sur iPhone).
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
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadTask?.cancel()
        loadTask = nil
    }
}