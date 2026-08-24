import Foundation

extension BeerAPI {
    /// Beerquest state — enabled=false si RPG off.
    func rpgMe() async throws -> RpgState {
        let (data, http, _) = try await request(path: "/api/rpg/me", method: "GET", body: nil)
        if http.statusCode == 401 { throw BeerAPIError.unauthorized }
        if http.statusCode == 403 { throw BeerAPIError.forbidden }
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            return RpgState(enabled: false)
        }
        return (try? JSONDecoder().decode(RpgState.self, from: data)) ?? RpgState(enabled: false)
    }
    func rpgSetClass(_ key: String) async throws -> Bool {
        let body = try JSONSerialization.data(withJSONObject: ["class": key])
        let (data, http, _) = try await request(
            path: "/api/rpg/class",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode >= 200 && http.statusCode < 300 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (obj["ok"] as? Bool) == true
            }
            return true
        }
        return false
    }
    func rpgIntroSeen() async throws -> Bool {
        let (data, http, _) = try await request(
            path: "/api/rpg/intro-seen",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        if http.statusCode >= 200 && http.statusCode < 300 {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return (obj["ok"] as? Bool) != false
            }
            return true
        }
        return false
    }
    func adminRpgPlayers() async throws -> [RpgAdminPlayer] {
        let decoded = try await adminRpgPlayersBundle()
        return decoded.players ?? []
    }
    func adminRpgPlayersBundle() async throws -> RpgAdminPlayersResponse {
        let (data, http, _) = try await request(path: "/api/admin/rpg/players", method: "GET", body: nil)
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Admin RPG indisponible")
        }
        return try JSONDecoder().decode(RpgAdminPlayersResponse.self, from: data)
    }
    func adminRpgGetSettings() async throws -> RpgAdminFlags {
        let (data, http, _) = try await request(path: "/api/admin/rpg/settings", method: "GET", body: nil)
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Réglages RPG indisponibles")
        }
        let decoded = try JSONDecoder().decode(RpgAdminSettingsResponse.self, from: data)
        return decoded.flags ?? RpgAdminFlags()
    }
    func adminRpgPatchSettings(_ payload: [String: Any]) async throws -> RpgAdminFlags {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/settings",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec réglages RPG")
        }
        let decoded = try JSONDecoder().decode(RpgAdminSettingsResponse.self, from: data)
        return decoded.flags ?? RpgAdminFlags()
    }
    /// allowed: true=force ON, false=force OFF, nil=auto (défaut)
    func adminRpgSetUserAllowed(username: String, allowed: Bool?) async throws {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let payload: [String: Any]
        if let allowed {
            payload = ["allowed": allowed]
        } else {
            payload = ["allowed": NSNull()]
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (_, http, _) = try await request(
            path: "/api/admin/rpg/settings/users/\(enc)",
            method: "PUT",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec accès user RPG")
        }
    }
    func adminRpgPlayer(_ username: String) async throws -> RpgAdminPlayerDetail {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)",
            method: "GET",
            body: nil
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Joueur introuvable")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }
    func adminRpgPatchPlayer(_ username: String, payload: [String: Any]) async throws -> RpgAdminPlayerDetail {
        let body = try JSONSerialization.data(withJSONObject: payload)
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec mise à jour profil")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }
    func adminRpgAdjustXp(username: String, delta: Int) async throws -> RpgAdminPlayerDetail {
        let body = try JSONSerialization.data(withJSONObject: ["delta": delta])
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/xp",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec XP")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }
    func adminRpgResetDaily(username: String) async throws -> RpgAdminPlayerDetail {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/reset-daily",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec reset journalier")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }
    func adminRpgGrantBadge(username: String, badgeKey: String) async throws -> RpgAdminPlayerDetail {
        let body = try JSONSerialization.data(withJSONObject: ["badge_key": badgeKey])
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/badges",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec badge")
        }
        // { granted, player: <admin_get_player detail> }
        if let wrap = try? JSONDecoder().decode(RpgAdminBadgeActionResponse.self, from: data),
           let detail = wrap.player {
            return detail
        }
        return try await adminRpgPlayer(username)
    }
    func adminRpgRevokeBadge(username: String, badgeKey: String) async throws -> RpgAdminPlayerDetail {
        let encU = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let encB = badgeKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? badgeKey
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(encU)/badges/\(encB)",
            method: "DELETE",
            body: nil
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec retrait badge")
        }
        if let wrap = try? JSONDecoder().decode(RpgAdminBadgeActionResponse.self, from: data),
           let detail = wrap.player {
            return detail
        }
        return try await adminRpgPlayer(username)
    }
    func adminRpgUnquarantine(_ username: String) async throws -> RpgAdminPlayerDetail {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (data, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/unquarantine",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec levée quarantaine")
        }
        return try JSONDecoder().decode(RpgAdminPlayerDetail.self, from: data)
    }
    func adminRpgWipe(username: String) async throws {
        let enc = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
        let (_, http, _) = try await request(
            path: "/api/admin/rpg/players/\(enc)/wipe",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        guard http.statusCode >= 200 && http.statusCode < 300 else {
            throw BeerAPIError.server("Échec wipe RPG")
        }
    }
}
