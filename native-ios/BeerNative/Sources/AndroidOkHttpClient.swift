import Foundation
import Network
import Security

/// **Un seul** transport invité = miroir d'OkHttp Android :
///
/// Android :
/// - URL reste `https://eiter.freeboxos.fr/beer/...` (ou IP en 2ᵉ candidat)
/// - `preferIpv4Dns` → socket sur l'**A** uniquement
/// - TLS SNI / Host = FQDN (cert LE normal, pas de bricolage hostname IP)
/// - connect 30s, read 120s
/// - si URL host = WAN_IPV4 → header Host = FQDN
///
/// iOS n'a pas de Dns custom URLSession → ce client fait le même job en un endroit.
enum AndroidOkHttpClient {
    private static let fqdn = ServerSettings.canonicalHost
    private static let wanIP = ServerSettings.wanIPv4

    /// Timeouts Android `buildClient(30, 120)`.
    static func perform(
        _ request: URLRequest,
        connectTimeout: TimeInterval = 30,
        readTimeout: TimeInterval = 120
    ) async throws -> (Data, HTTPURLResponse, URL) {
        guard let url = request.url else { throw BeerAPIError.invalidURL }

        let urlHost = url.host ?? fqdn
        // Dial IPv4 only (preferIpv4Dns)
        let dialIP: String = {
            if isIPv4Literal(urlHost) { return urlHost }
            return PreferIPv4.firstIPv4(urlHost)
                ?? PreferIPv4.firstIPv4(fqdn)
                ?? wanIP
        }()
        // SNI + Host HTTP = toujours le FQDN pour le cert LE (comme OkHttp avec URL FQDN)
        let tlsAndHttpHost = fqdn

        let path: String = {
            var p = url.path
            if p.isEmpty { p = "/" }
            if let q = url.query { p += "?\(q)" }
            return p
        }()
        let method = request.httpMethod ?? "GET"
        let body = request.httpBody ?? Data()

        let totalTimeout = UInt64(connectTimeout + readTimeout)
        return try await withThrowingTaskGroup(of: (Data, HTTPURLResponse, URL).self) { group in
            group.addTask {
                try await dialAndExchange(
                    dialIP: dialIP,
                    tlsHost: tlsAndHttpHost,
                    method: method,
                    path: path,
                    request: request,
                    body: body,
                    logicalURL: url,
                    connectTimeout: connectTimeout
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: totalTimeout * 1_000_000_000)
                throw BeerAPIError.server("Timeout \(Int(totalTimeout))s")
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw BeerAPIError.server("Timeout")
            }
            return result
        }
    }

    private static func dialAndExchange(
        dialIP: String,
        tlsHost: String,
        method: String,
        path: String,
        request: URLRequest,
        body: Data,
        logicalURL: URL,
        connectTimeout: TimeInterval
    ) async throws -> (Data, HTTPURLResponse, URL) {
        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = Int(max(connectTimeout, 5))
        tcp.noDelay = true

        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions
        // SNI = FQDN (OkHttp ne met PAS l'IP en SNI sur le chemin principal)
        sec_protocol_options_set_tls_server_name(sec, tlsHost)
        sec_protocol_options_set_verify_block(sec, { _, secTrust, complete in
            let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()
            // Cert LE pour eiter.freeboxos.fr — éval standard domaine
            let policy = SecPolicyCreateSSL(true, tlsHost as CFString)
            SecTrustSetPolicies(trust, policy)
            var err: CFError?
            complete(SecTrustEvaluateWithError(trust, &err))
        }, .global())

        let params = NWParameters(tls: tls, tcp: tcp)
        params.prohibitExpensivePaths = false
        params.prohibitConstrainedPaths = false

        // Logs techniques OK ; erreurs user = FQDN uniquement (jamais l’IP)
        NSLog("AndroidOkHttp: %@ %@ host=%@ dial-v4-internal SNI=%@", method, path, tlsHost, tlsHost)

        let conn = NWConnection(host: NWEndpoint.Host(dialIP), port: 443, using: params)
        return try await withCheckedThrowingContinuation { cont in
            let queue = DispatchQueue(label: "fr.eiter.plexibeer.android-okhttp")
            var resumed = false
            func finish(_ r: Result<(Data, HTTPURLResponse, URL), Error>) {
                guard !resumed else { return }
                resumed = true
                conn.cancel()
                cont.resume(with: r)
            }

            let connectWatch = Task {
                try? await Task.sleep(nanoseconds: UInt64(connectTimeout) * 1_000_000_000)
                if !resumed {
                    finish(.failure(BeerAPIError.server(
                        "Timeout connexion \(Int(connectTimeout))s — \(tlsHost)"
                    )))
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connectWatch.cancel()
                    Task {
                        do {
                            let out = try await exchange(
                                conn: conn,
                                method: method,
                                path: path,
                                request: request,
                                body: body,
                                hostHeader: tlsHost,
                                logicalURL: logicalURL
                            )
                            finish(.success(out))
                        } catch {
                            finish(.failure(error))
                        }
                    }
                case .failed(let err):
                    connectWatch.cancel()
                    finish(.failure(BeerAPIError.server(
                        "Connexion \(tlsHost) échouée: \(err.localizedDescription)"
                    )))
                case .waiting(let err):
                    // 5G : laisser jusqu'au connectTimeout — pas de kill 3s
                    NSLog("AndroidOkHttp: waiting %@", err.localizedDescription)
                case .cancelled:
                    connectWatch.cancel()
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
        hostHeader: String,
        logicalURL: URL
    ) async throws -> (Data, HTTPURLResponse, URL) {
        var lines = [
            "\(method) \(path) HTTP/1.1",
            "Host: \(hostHeader)",
            "Accept: */*",
            "Accept-Encoding: identity",
            "Connection: close",
        ]
        if !body.isEmpty {
            lines.append("Content-Length: \(body.count)")
        }
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            let low = key.lowercased()
            if low == "host" || low == "connection" || low == "accept-encoding"
                || low == "content-length" { continue }
            lines.append("\(key): \(value)")
        }
        var payload = (lines.joined(separator: "\r\n") + "\r\n\r\n").data(using: .utf8) ?? Data()
        payload.append(body)

        try await send(conn, payload)
        let (headerData, bodyData) = try await receive(conn)
        let responseURL = URL(string: "https://\(hostHeader)\(path)") ?? logicalURL
        let parsed = try parseHTTP(headerData + bodyData, url: responseURL)
        // Cookies comme URLSession
        let storeURL = URL(string: "https://\(hostHeader)/beer/")!
        for line in parsed.setCookies {
            for c in HTTPCookie.cookies(withResponseHeaderFields: ["Set-Cookie": line], for: storeURL) {
                HTTPCookieStorage.shared.setCookie(c)
            }
        }
        return (parsed.body, parsed.response, responseURL)
    }

    private static func send(_ conn: NWConnection, _ data: Data) async throws {
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

    private static func receive(_ conn: NWConnection) async throws -> (Data, Data) {
        var buffer = Data()
        while true {
            let (chunk, done): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, complete, err in
                    if let err {
                        cont.resume(throwing: BeerAPIError.server("Réception: \(err.localizedDescription)"))
                        return
                    }
                    cont.resume(returning: (data, complete))
                }
            }
            if let chunk, !chunk.isEmpty { buffer.append(chunk) }
            if buffer.range(of: Data([13, 10, 13, 10])) != nil { break }
            if done || buffer.count > 64 * 1024 { break }
        }
        guard let sep = buffer.range(of: Data([13, 10, 13, 10])) else {
            throw BeerAPIError.server("Réponse HTTP invalide")
        }
        let headerData = buffer.subdata(in: 0..<sep.upperBound)
        var body = buffer.subdata(in: sep.upperBound..<buffer.count)
        let headerText = String(data: headerData, encoding: .utf8) ?? ""
        var contentLength: Int?
        for line in headerText.split(separator: "\n") {
            let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.lowercased().hasPrefix("content-length:"),
               let v = Int(t.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) {
                contentLength = v
            }
        }
        if let need = contentLength {
            while body.count < need && body.count < 2 * 1024 * 1024 {
                let (chunk, _): (Data?, Bool) = try await withCheckedThrowingContinuation { cont in
                    conn.receive(minimumIncompleteLength: 0, maximumLength: 65536) { data, _, complete, err in
                        if let err {
                            cont.resume(throwing: BeerAPIError.server("Body: \(err.localizedDescription)"))
                            return
                        }
                        cont.resume(returning: (data, complete))
                    }
                }
                if let chunk, !chunk.isEmpty { body.append(chunk) } else { break }
            }
        }
        return (headerData, body)
    }

    private struct Parsed {
        let body: Data
        let response: HTTPURLResponse
        let setCookies: [String]
    }

    private static func parseHTTP(_ raw: Data, url: URL) throws -> Parsed {
        guard let sep = raw.range(of: Data([13, 10, 13, 10])) else { throw BeerAPIError.decode }
        let headerText = String(data: raw.subdata(in: 0..<sep.lowerBound), encoding: .utf8) ?? ""
        let body = raw.subdata(in: sep.upperBound..<raw.count)
        var status = 0
        var headers: [String: String] = [:]
        var setCookies: [String] = []
        for (i, line) in headerText.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let t = line.trimmingCharacters(in: .init(charactersIn: "\r"))
            if i == 0 {
                let parts = t.split(separator: " ")
                if parts.count >= 2 { status = Int(parts[1]) ?? 0 }
            } else if let c = t.firstIndex(of: ":") {
                let k = String(t[..<c]).trimmingCharacters(in: .whitespaces)
                let v = String(t[t.index(after: c)...]).trimmingCharacters(in: .whitespaces)
                if k.lowercased() == "set-cookie" { setCookies.append(v) }
                else { headers[k] = v }
            }
        }
        guard status > 0,
              let http = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)
        else { throw BeerAPIError.decode }
        return Parsed(body: body, response: http, setCookies: setCookies)
    }

    private static func isIPv4Literal(_ s: String) -> Bool {
        var a = in_addr()
        return s.withCString { inet_pton(AF_INET, $0, &a) } == 1
    }
}
