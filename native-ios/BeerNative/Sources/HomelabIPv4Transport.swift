import Foundation
import Network

/// HTTPS vers l'IP WAN avec SNI = FQDN (contourne l'AAAA Freebox ::1 en 4G).
enum HomelabIPv4Transport {
    private static let wanIP = ServerSettings.wanIPv4
    private static let tlsHost = ServerSettings.canonicalHost

    private static var cookieURL: URL {
        URL(string: "https://\(tlsHost)/beer/")!
    }

    static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        guard let url = request.url else { throw BeerAPIError.invalidURL }

        let path = {
            var p = url.path
            if p.isEmpty { p = "/" }
            if let q = url.query { p += "?\(q)" }
            return p
        }()
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? Data()

        let tcp = NWProtocolTCP.Options()
        let tls = NWProtocolTLS.Options()
        sec_protocol_options_set_tls_server_name(tls.securityProtocolOptions, tlsHost)
        let params = NWParameters(tls: tls, tcp: tcp)

        let conn = NWConnection(host: NWEndpoint.Host(wanIP), port: 443, using: params)
        return try await withCheckedThrowingContinuation { cont in
            let queue = DispatchQueue(label: "fr.eiter.plexibeer.ipv4")
            var resumed = false
            func finish(_ result: Result<(Data, HTTPURLResponse, URL), Error>) {
                guard !resumed else { return }
                resumed = true
                conn.cancel()
                cont.resume(with: result)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task {
                        do {
                            let out = try await exchange(conn: conn, method: method, path: path, request: request, body: body, url: url)
                            finish(.success(out))
                        } catch {
                            finish(.failure(error))
                        }
                    }
                case .failed(let err):
                    finish(.failure(BeerAPIError.network(err)))
                case .cancelled:
                    if !resumed {
                        finish(.failure(BeerAPIError.server("Connexion interrompue")))
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    private static func exchange(
        conn: NWConnection,
        method: String,
        path: String,
        request: URLRequest,
        body: Data,
        url: URL
    ) async throws -> (Data, HTTPURLResponse, URL) {
        var lines = ["\(method) \(path) HTTP/1.1", "Host: \(tlsHost)", "Accept: */*", "Accept-Encoding: identity", "Connection: close"]
        if !body.isEmpty {
            lines.append("Content-Length: \(body.count)")
        }
        if let cookieLine = cookieHeader() {
            lines.append("Cookie: \(cookieLine)")
        }
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let low = key.lowercased()
            if low == "host" || low == "connection" || low == "accept-encoding" || low == "cookie" { continue }
            lines.append("\(key): \(value)")
        }
        var payload = (lines.joined(separator: "\r\n") + "\r\n\r\n").data(using: .utf8) ?? Data()
        payload.append(body)

        try await send(conn: conn, data: payload)
        let raw = try await receive(conn: conn)
        let parsed = try parseHTTP(raw, url: url)
        storeCookies(from: parsed.setCookieLines)
        return (parsed.body, parsed.response, url)
    }

    private static func cookieHeader() -> String? {
        let stored = HTTPCookieStorage.shared.cookies(for: cookieURL) ?? []
        guard !stored.isEmpty else { return nil }
        return stored.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func storeCookies(from setCookieLines: [String]) {
        for line in setCookieLines {
            guard let cookie = makeCookie(from: line) else { continue }
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }

    /// Cookies reçus via IP WAN : forcer le domaine FQDN pour les requêtes suivantes.
    private static func makeCookie(from line: String) -> HTTPCookie? {
        let parts = line.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let first = parts.first, let eq = first.firstIndex(of: "=") else { return nil }
        let name = String(first[..<eq])
        let value = String(first[first.index(after: eq)...])

        var path = "/beer"
        var maxAge: Int?
        var secure = true
        for attr in parts.dropFirst() {
            let lower = attr.lowercased()
            if lower.hasPrefix("path=") {
                path = String(attr.dropFirst(5))
            } else if lower.hasPrefix("max-age=") {
                maxAge = Int(attr.dropFirst(8))
            } else if lower == "secure" {
                secure = true
            }
        }

        var props: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: tlsHost,
            .path: path,
            .secure: secure,
        ]
        if let maxAge { props[.maximumAge] = maxAge }
        return HTTPCookie(properties: props)
    }

    private static func send(conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: BeerAPIError.network(err)) }
                else { cont.resume() }
            })
        }
    }

    private static func receive(conn: NWConnection) async throws -> Data {
        var buffer = Data()
        while true {
            let (chunk, complete): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
                    if let err {
                        cont.resume(throwing: BeerAPIError.network(err))
                        return
                    }
                    cont.resume(returning: (data, isComplete))
                }
            }
            if let chunk, !chunk.isEmpty { buffer.append(chunk) }
            if complete { break }
        }
        guard !buffer.isEmpty else { throw BeerAPIError.server("Réponse vide") }
        return buffer
    }

    private struct ParsedHTTP {
        let body: Data
        let response: HTTPURLResponse
        let setCookieLines: [String]
    }

    private static func parseHTTP(_ raw: Data, url: URL) throws -> ParsedHTTP {
        guard let sep = raw.range(of: Data([13, 10, 13, 10])) ?? raw.range(of: Data([10, 10])) else {
            throw BeerAPIError.decode
        }
        let headerData = raw.subdata(in: 0..<sep.lowerBound)
        let body = raw.subdata(in: sep.upperBound..<raw.count)
        guard let headerText = String(data: headerData, encoding: .utf8) else { throw BeerAPIError.decode }

        var status = 0
        var headers = [String: String]()
        var setCookies: [String] = []
        for (idx, line) in headerText.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))
            if idx == 0 {
                let parts = trimmed.split(separator: " ")
                if parts.count >= 2, let code = Int(parts[1]) { status = code }
            } else if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if key.lowercased() == "set-cookie" {
                    setCookies.append(val)
                } else {
                    headers[key] = val
                }
            }
        }
        guard status > 0,
              let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            throw BeerAPIError.decode
        }
        return ParsedHTTP(body: body, response: http, setCookieLines: setCookies)
    }
}