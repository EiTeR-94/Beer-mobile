import Foundation
import Network

/// Couche TCP IPv4+SNI pour PlexiIPv4URLProtocol — pas d'usage direct (cookies = URLSession).
enum HomelabIPv4Transport {
    private static let wanIP = ServerSettings.wanIPv4
    private static let tlsHost = ServerSettings.canonicalHost
    private static let timeoutSeconds: UInt64 = 15

    static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        try await withThrowingTaskGroup(of: (Data, HTTPURLResponse, URL).self) { group in
            group.addTask { try await performOnce(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw BeerAPIError.server("Timeout serveur (5G)")
            }
            guard let result = try await group.next() else {
                throw BeerAPIError.server("Timeout serveur (5G)")
            }
            group.cancelAll()
            return result
        }
    }

    private static func performOnce(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
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
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let low = key.lowercased()
            if low == "host" || low == "connection" || low == "accept-encoding" { continue }
            lines.append("\(key): \(value)")
        }
        var payload = (lines.joined(separator: "\r\n") + "\r\n\r\n").data(using: .utf8) ?? Data()
        payload.append(body)

        try await send(conn: conn, data: payload)
        let raw = try await receive(conn: conn)
        let parsed = try parseHTTP(raw, url: url)
        storeCookiesForURLSession(parsed.setCookieLines, url: url)
        return (parsed.body, parsed.response, url)
    }

    /// Parse Set-Cookie comme URLSession (domaine FQDN de la requête).
    private static func storeCookiesForURLSession(_ lines: [String], url: URL) {
        for line in lines {
            let fields = ["Set-Cookie": line]
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
            HTTPCookieStorage.shared.setCookies(cookies)
        }
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