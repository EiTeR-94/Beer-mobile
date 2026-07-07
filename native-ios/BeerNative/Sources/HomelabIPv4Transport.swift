import Foundation
import Network

/// TCP/TLS IPv4 + SNI pour passkey/Face ID quand l'iPhone tente l'AAAA morte en premier.
enum HomelabIPv4Transport {
    private static let wanIP = ServerSettings.wanIPv4
    private static let tlsHost = ServerSettings.canonicalHost
    private static let timeoutSeconds: UInt64 = 25

    static func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse, URL) {
        try await withThrowingTaskGroup(of: (Data, HTTPURLResponse, URL).self) { group in
            group.addTask { try await performOnce(request) }
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutSeconds * 1_000_000_000)
                throw BeerAPIError.server("Timeout serveur")
            }
            guard let result = try await group.next() else {
                throw BeerAPIError.server("Timeout serveur")
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
        if let cookieLine = mergedCookieHeader(for: request, url: url) {
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
        let (headersData, bodyData) = try await receiveResponse(conn: conn)
        let raw = headersData + bodyData
        let parsed = try parseHTTP(raw, url: url)
        storeCookiesForURLSession(parsed.setCookieLines)
        // Close promptly; do not rely on server FIN for body end
        conn.cancel()
        return (parsed.body, parsed.response, url)
    }

    private static func storeCookiesForURLSession(_ lines: [String]) {
        let storeURL = URL(string: "https://\(tlsHost)/beer/")!
        for line in lines {
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": line], for: storeURL)
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }

    private static func mergedCookieHeader(for request: URLRequest, url: URL) -> String? {
        var byName: [String: String] = [:]
        func ingest(_ header: String) {
            for part in header.split(separator: ";") {
                let piece = part.trimmingCharacters(in: .whitespaces)
                guard let eq = piece.firstIndex(of: "=") else { continue }
                byName[String(piece[..<eq])] = String(piece[piece.index(after: eq)...])
            }
        }
        if let existing = request.value(forHTTPHeaderField: "Cookie") { ingest(existing) }
        for cookie in HTTPCookieStorage.shared.cookies(for: ServerSettings.apiBase) ?? [] {
            byName[cookie.name] = cookie.value
        }
        guard !byName.isEmpty else { return nil }
        return byName.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private static func send(conn: NWConnection, data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: BeerAPIError.network(err)) }
                else { cont.resume() }
            })
        }
    }

    /// Receive headers (until blank line) then body using Content-Length when present.
    /// Avoids hanging on servers that delay FIN despite "Connection: close".
    private static func receiveResponse(conn: NWConnection) async throws -> (Data, Data) {
        var buffer = Data()
        // Read until we have headers separator
        while true {
            let (chunk, _): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
                    if let err {
                        cont.resume(throwing: BeerAPIError.network(err))
                        return
                    }
                    cont.resume(returning: (data, isComplete))
                }
            }
            if let chunk, !chunk.isEmpty { buffer.append(chunk) }
            if buffer.range(of: Data([13, 10, 13, 10])) != nil || buffer.range(of: Data([10, 10])) != nil {
                break
            }
            // safety to avoid infinite on broken
            if buffer.count > 64 * 1024 { break }
        }
        guard !buffer.isEmpty else { throw BeerAPIError.server("Réponse vide") }

        // Parse just enough to find Content-Length
        guard let sepRange = buffer.range(of: Data([13, 10, 13, 10])) ?? buffer.range(of: Data([10, 10])) else {
            throw BeerAPIError.server("Réponse invalide (pas de séparateur headers)")
        }
        let headerEnd = sepRange.upperBound
        let headerData = buffer.subdata(in: 0..<headerEnd)
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        var contentLength: Int? = nil
        for line in headerText.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let colon = t.firstIndex(of: ":") {
                let k = String(t[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                if k == "content-length" {
                    if let v = Int(String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces)) {
                        contentLength = v
                    }
                }
            }
        }

        var body = buffer.subdata(in: headerEnd..<buffer.count)
        if let needed = contentLength {
            while body.count < needed && body.count < 2*1024*1024 {
                let toRead = min(needed - body.count, 65536)
                let (chunk, _): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                    conn.receive(minimumIncompleteLength: 0, maximumLength: toRead) { data, _, isComplete, err in
                        if let err {
                            cont.resume(throwing: BeerAPIError.network(err))
                            return
                        }
                        cont.resume(returning: (data, isComplete))
                    }
                }
                if let chunk, !chunk.isEmpty {
                    body.append(chunk)
                } else {
                    break
                }
            }
        } else {
            // No content-length: read until connection closes or reasonable max
            var safety = 0
            while safety < 100 {
                let (chunk, isComplete): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
                        if let err {
                            cont.resume(throwing: BeerAPIError.network(err))
                            return
                        }
                        cont.resume(returning: (data, isComplete))
                    }
                }
                if let chunk, !chunk.isEmpty {
                    body.append(chunk)
                }
                if isComplete { break }
                safety += 1
                if body.count > 2*1024*1024 { break }
            }
        }
        return (headerData, body)
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
                if key.lowercased() == "set-cookie" { setCookies.append(val) }
                else { headers[key] = val }
            }
        }
        guard status > 0,
              let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
            throw BeerAPIError.decode
        }
        return ParsedHTTP(body: body, response: http, setCookieLines: setCookies)
    }
}