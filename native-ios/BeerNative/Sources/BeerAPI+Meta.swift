import Foundation

extension BeerAPI {
    /// Manifest versions natives (portail public, sans session).
    func fetchMobileVersions() async -> MobileVersionsManifest? {
        guard let url = URL(string: ServerSettings.versionsURLString) else { return nil }
        do {
            var req = URLRequest(url: url)
            req.timeoutInterval = 8
            req.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
            return try? JSONDecoder().decode(MobileVersionsManifest.self, from: data)
        } catch {
            return nil
        }
    }
    func version() async throws -> String {
        let (data, _, _) = try await request(path: "/api/version", method: "GET", body: nil)
        struct V: Decodable { let version: String? }
        return (try? JSONDecoder().decode(V.self, from: data))?.version ?? "?"
    }
    func patchnotes() async throws -> PatchnotesResponse {
        let (data, http, _) = try await request(path: "/api/admin/patchnotes", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        guard let decoded = try? JSONDecoder().decode(PatchnotesResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }
    func downloadAsset(_ pathOrURL: String?) async throws -> Data {
        guard let p = pathOrURL, !p.isEmpty else {
            throw BeerAPIError.invalidURL
        }

        if p.hasPrefix("http://") || p.hasPrefix("https://") {
            // External asset (e.g. Untappd search result labels, or other third-party images).
            // Use plain system networking — do NOT go through homelab transport, cookie injection,
            // (IPv4 forcing for LAN cert bypass)
            guard let url = URL(string: p) else { throw BeerAPIError.invalidURL }
            // Theme 3: retry with backoff also for external photos (centralized)
            return try await NetworkManager.shared.withRetry(maxAttempts: 3, baseDelayMs: 400) {
                let (data, resp) = try await URLSession.shared.data(from: url)
                if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                    throw BeerAPIError.server("Fichier externe HTTP \(http.statusCode)")
                }
                return data
            }
        }

        // Internal server asset (relative path like "photos/..." or "static/...").
        // Always try LAN IP first for owner (fast direct, no domain transport).
        // If fails (e.g. on VPN where LAN IP not reachable), fallback to current base.
        guard let lanResolved = ServerSettings.resolveAssetURL(p, base: ServerSettings.lanApiBase) else {
            throw BeerAPIError.invalidURL
        }
        var req = URLRequest(url: lanResolved)
        do {
            return try await NetworkManager.shared.withRetry(maxAttempts: 3, baseDelayMs: 400) {
                let (data, http, _) = try await self.performTransport(req)
                try self.throwIfUnauthorized(http.statusCode)
                if http.statusCode != 200 { throw BeerAPIError.server("Fichier HTTP \(http.statusCode)") }
                return data
            }
        } catch {
            // fallback to current base (domain for VPN)
            guard let resolved = ServerSettings.resolveAssetURL(p, base: baseURL) else {
                throw BeerAPIError.invalidURL
            }
            req = URLRequest(url: resolved)
            return try await NetworkManager.shared.withRetry(maxAttempts: 3, baseDelayMs: 400) {
                let (data, http, _) = try await self.performTransport(req)
                try self.throwIfUnauthorized(http.statusCode)
                if http.statusCode != 200 { throw BeerAPIError.server("Fichier HTTP \(http.statusCode)") }
                return data
            }
        }
    }
}
