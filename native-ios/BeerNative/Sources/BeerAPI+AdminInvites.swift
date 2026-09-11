import Foundation

extension BeerAPI {
    func adminInvites() async throws -> [InviteItem] {
        let (data, http, _) = try await request(path: "/api/invites", method: "GET", body: nil)
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        return (try? JSONDecoder().decode([InviteItem].self, from: data)) ?? []
    }
    /// Admin : dégustations d'un invité (lecture seule).
    func adminInviteCheckins(inviteId: Int, limit: Int = 30, offset: Int = 0) async throws -> [CheckinItem] {
        let (data, http, _) = try await request(
            path: "/api/invites/\(inviteId)/checkins?limit=\(limit)&offset=\(offset)",
            method: "GET",
            body: nil
        )
        if http.statusCode == 401 || http.statusCode == 403 {
            if http.statusCode == 401 { NotificationCenter.default.post(name: .beerAuthExpired, object: nil) }
            throw BeerAPIError.unauthorized
        }
        if http.statusCode == 404 {
            throw BeerAPIError.server("Invitation introuvable")
        }
        return (try? JSONDecoder().decode([CheckinItem].self, from: data)) ?? []
    }
    func adminExtendInvite(id: Int, validity: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["validity": validity])
        let (data, http, _) = try await request(
            path: "/api/invites/\(id)/extend",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        if http.statusCode >= 400 {
            let err = (try? JSONDecoder().decode(OKResponse.self, from: data))?.error
            throw BeerAPIError.server(err ?? "Prolongation impossible")
        }
    }
}
