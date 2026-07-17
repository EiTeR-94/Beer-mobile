import Foundation
import Network
import Security

/// Transport WAN invite = miroir exact d'OkHttp Android `preferIpv4Dns` :
/// 1) dial **IPv4 only** (enregistrement A / `wanIPv4`)
/// 2) TLS **SNI** = `eiter.freeboxos.fr` (cert LE normal)
/// 3) HTTP **Host** = même FQDN
///
/// URLSession seul sur le FQDN fait Happy Eyeballs → AAAA Freebox morte → SSL/timeout aléatoire.
/// Rewrite URL en IP casse le SNI (Host header souvent écrasé par CFNetwork).
///
/// Fallback déterministe (pas aléatoire) : si NWConnection échoue, PreferIPv4+URLSession+HomelabTLS.
enum HomelabIPv4Transport {
    private static let wanIP = ServerSettings.wanIPv4
    private static let tlsHost = ServerSettings.canonicalHost

    /// Point d'entrée unique pour tout le trafic invite/WAN.
    static func perform(_ request: URLRequest, timeoutSeconds: UInt64 = 30) async throws -> (Data, HTTPURLResponse, URL) {
        var lastError: Error?
        // 2 tentatives NW (micro blip 5G), puis fallback URLSession IPv4
        for attempt in 1...2 {
            do {
                return try await performNW(request, timeoutSeconds: timeoutSeconds)
            } catch {
                lastError = error
                NSLog("HomelabIPv4: NW attempt %d failed: %@", attempt, "\(error)")
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        do {
            NSLog("HomelabIPv4: fallback PreferIPv4+URLSession")
            return try await performURLSessionFallback(request, timeoutSeconds: timeoutSeconds)
        } catch {
            throw lastError ?? error
        }
    }

    // MARK: - Primary: Network.framework IPv4 + SNI FQDN

    private static func performNW(_ request: URLRequest, timeoutSeconds: UInt64) async throws -> (Data, HTTPURLResponse, URL) {
        guard let url = request.url else { throw BeerAPIError.invalidURL }

        let path: String = {
            var p = url.path
            if p.isEmpty { p = "/" }
            if let q = url.query { p += "?\(q)" }
            return p
        }()
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? Data()

        let dialIP = PreferIPv4.firstIPv4(tlsHost) ?? wanIP
        guard let ipv4 = IPv4Address(dialIP) else {
            throw BeerAPIError.server("IPv4 invalide pour \(tlsHost)")
        }

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(min(max(timeoutSeconds, 10), 45))
        tcp.noDelay = true
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 10

        let tls = NWProtocolTLS.Options()
        let secOpts = tls.securityProtocolOptions
        sec_protocol_options_set_tls_server_name(secOpts, tlsHost)
        sec_protocol_options_add_tls_application_protocol(secOpts, "http/1.1")
        sec_protocol_options_set_verify_block(secOpts, { _, secTrust, complete in
            let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
            complete(evaluateTrust(trust))
        }, .global())

        let params = NWParameters(tls: tls, tcp: tcp)
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false
        params.allowLocalEndpointReuse = true
        if #available(iOS 17.0, *) {
            params.preferNoProxies = true
        }

        NSLog("HomelabIPv4: dial %@ SNI=%@ path=%@", dialIP, tlsHost, path)
        let conn = NWConnection(
            host: NWEndpoint.Host.ipv4(ipv4),
            port: 443,
            using: params
        )

        return try await withCheckedThrowingContinuation { cont in
            let queue = DispatchQueue(label: "fr.eiter.plexibeer.ipv4", qos: .userInitiated)
            let lock = NSLock()
            var resumed = false
            func finish(_ result: Result<(Data, HTTPURLResponse, URL), Error>) {
                lock.lock()
                let already = resumed
                if !already { resumed = true }
                lock.unlock()
                guard !already else { return }
                // cancel HORS du lock (évite deadlock si stateUpdate re-entrant)
                conn.cancel()
                cont.resume(with: result)
            }

            let deadline = DispatchTime.now() + .seconds(Int(timeoutSeconds))
            queue.asyncAfter(deadline: deadline) {
                finish(.failure(BeerAPIError.server("Timeout \(timeoutSeconds)s — \(tlsHost)")))
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task {
                        do {
                            let out = try await exchange(
                                conn: conn,
                                method: method,
                                path: path,
                                request: request,
                                body: body,
                                url: url
                            )
                            finish(.success(out))
                        } catch {
                            finish(.failure(error))
                        }
                    }
                case .failed(let err):
                    finish(.failure(BeerAPIError.server(
                        "Connexion \(tlsHost) échouée: \(err.localizedDescription)"
                    )))
                case .waiting(let err):
                    // Laisser NW retry jusqu'au deadline (5G path establishment)
                    NSLog("HomelabIPv4: waiting %@", err.localizedDescription)
                case .cancelled:
                    // Ignore : cancel volontaire après succès/timeout
                    break
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    private static func evaluateTrust(_ trust: SecTrust) -> Bool {
        var error: CFError?
        let ssl = SecPolicyCreateSSL(true, tlsHost as CFString)
        SecTrustSetPolicies(trust, ssl)
        if SecTrustEvaluateWithError(trust, &error) {
            return true
        }
        let basic = SecPolicyCreateBasicX509()
        SecTrustSetPolicies(trust, basic)
        error = nil
        if SecTrustEvaluateWithError(trust, &error), leafMatchesDomain(trust) {
            return true
        }
        return leafMatchesDomain(trust)
    }

    private static func leafMatchesDomain(_ trust: SecTrust) -> Bool {
        guard let cfArr = SecTrustCopyCertificateChain(trust) else { return false }
        let n = CFArrayGetCount(cfArr)
        guard n > 0 else { return false }
        let cert = unsafeBitCast(CFArrayGetValueAtIndex(cfArr, 0), to: SecCertificate.self)
        if let summary = SecCertificateCopySubjectSummary(cert) as String?,
           summary.localizedCaseInsensitiveContains(tlsHost) {
            return true
        }
        let data = SecCertificateCopyData(cert) as Data
        if let needle = tlsHost.data(using: .utf8), data.range(of: needle) != nil {
            return true
        }
        return false
    }

    // MARK: - Fallback: PreferIPv4 rewrite + URLSession + HomelabTLS

    private static func performURLSessionFallback(
        _ request: URLRequest,
        timeoutSeconds: UInt64
    ) async throws -> (Data, HTTPURLResponse, URL) {
        var req = request
        // URL logique FQDN puis rewrite A (évite AAAA)
        if var c = URLComponents(url: req.url ?? ServerSettings.apiBase, resolvingAgainstBaseURL: false) {
            c.host = tlsHost
            c.scheme = "https"
            c.port = nil
            if let u = c.url { req.url = u }
        }
        PreferIPv4.applyAndroidStyle(&req)
        req.timeoutInterval = TimeInterval(timeoutSeconds)

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = TimeInterval(timeoutSeconds)
        cfg.timeoutIntervalForResource = TimeInterval(timeoutSeconds) + 30
        cfg.waitsForConnectivity = false
        cfg.httpShouldSetCookies = false
        cfg.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: cfg, delegate: HomelabTLSDelegate.shared, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BeerAPIError.decode }
        let logical = URL(string: "https://\(tlsHost)\(req.url?.path ?? "/beer/")") ?? response.url ?? ServerSettings.apiBase
        if let setCookie = http.value(forHTTPHeaderField: "Set-Cookie"), !setCookie.isEmpty {
            storeCookiesForURLSession([setCookie])
        }
        return (data, http, logical)
    }

    // MARK: - HTTP/1.1 exchange

    private static func exchange(
        conn: NWConnection,
        method: String,
        path: String,
        request: URLRequest,
        body: Data,
        url: URL
    ) async throws -> (Data, HTTPURLResponse, URL) {
        var lines = [
            "\(method) \(path) HTTP/1.1",
            "Host: \(tlsHost)",
            "Accept: */*",
            "Accept-Encoding: identity",
            "Connection: close",
        ]
        if !body.isEmpty {
            lines.append("Content-Length: \(body.count)")
        }
        if let cookieLine = mergedCookieHeader(for: request, url: url) {
            lines.append("Cookie: \(cookieLine)")
        }
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let low = key.lowercased()
            if low == "host" || low == "connection" || low == "accept-encoding"
                || low == "cookie" || low == "content-length" { continue }
            lines.append("\(key): \(value)")
        }
        var payload = (lines.joined(separator: "\r\n") + "\r\n\r\n").data(using: .utf8) ?? Data()
        payload.append(body)

        try await send(conn: conn, data: payload)
        let (headersData, bodyData) = try await receiveResponse(conn: conn)
        let raw = headersData + bodyData
        let logical = URL(string: "https://\(tlsHost)\(path)") ?? url
        let parsed = try parseHTTP(raw, url: logical)
        storeCookiesForURLSession(parsed.setCookieLines)
        conn.cancel()
        return (parsed.body, parsed.response, logical)
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
                if let err {
                    cont.resume(throwing: BeerAPIError.server("Envoi: \(err.localizedDescription)"))
                } else {
                    cont.resume()
                }
            })
        }
    }

    private static func receiveResponse(conn: NWConnection) async throws -> (Data, Data) {
        var buffer = Data()
        while true {
            let (chunk, isComplete): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
                    if let err {
                        cont.resume(throwing: BeerAPIError.server("Réception: \(err.localizedDescription)"))
                        return
                    }
                    cont.resume(returning: (data, isComplete))
                }
            }
            if let chunk, !chunk.isEmpty { buffer.append(chunk) }
            if buffer.range(of: Data([13, 10, 13, 10])) != nil || buffer.range(of: Data([10, 10])) != nil {
                break
            }
            if isComplete || buffer.count > 64 * 1024 { break }
        }
        guard !buffer.isEmpty else { throw BeerAPIError.server("Réponse vide") }

        guard let sepRange = buffer.range(of: Data([13, 10, 13, 10])) ?? buffer.range(of: Data([10, 10])) else {
            throw BeerAPIError.server("Réponse invalide (headers)")
        }
        let headerEnd = sepRange.upperBound
        let headerData = buffer.subdata(in: 0..<headerEnd)
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        var contentLength: Int?
        for line in headerText.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let colon = t.firstIndex(of: ":") {
                let k = String(t[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                if k == "content-length" {
                    contentLength = Int(String(t[t.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
                }
            }
        }

        var body = buffer.subdata(in: headerEnd..<buffer.count)
        if let needed = contentLength {
            while body.count < needed && body.count < 2 * 1024 * 1024 {
                let toRead = min(needed - body.count, 65536)
                let (chunk, _): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                    conn.receive(minimumIncompleteLength: 0, maximumLength: toRead) { data, _, isComplete, err in
                        if let err {
                            cont.resume(throwing: BeerAPIError.server("Body: \(err.localizedDescription)"))
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
            var safety = 0
            while safety < 40 {
                let (chunk, isComplete): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, err in
                        if let err {
                            cont.resume(throwing: BeerAPIError.server("Body: \(err.localizedDescription)"))
                            return
                        }
                        cont.resume(returning: (data, isComplete))
                    }
                }
                if let chunk, !chunk.isEmpty { body.append(chunk) }
                if isComplete { break }
                safety += 1
                if body.count > 2 * 1024 * 1024 { break }
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
