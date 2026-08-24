import Foundation

extension BeerAPI {
    /// Feedback joueur (parité PWA « Un retour »).
    func sendFeedback(message: String, category: String = "general", appVersion: String = "") async -> (Bool, String?) {
        var payload: [String: Any] = [
            "message": message,
            "category": category,
            "client_info": "native-ios",
            "page_path": "native/ios",
        ]
        if !appVersion.isEmpty {
            payload["app_version"] = appVersion
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            return (false, "JSON invalide")
        }
        do {
            let (data, http, _) = try await request(
                path: "/api/feedback",
                method: "POST",
                body: body,
                contentType: "application/json"
            )
            if (200..<300).contains(http.statusCode) {
                return (true, nil)
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let detail = obj["detail"] as? String {
                return (false, detail)
            }
            return (false, "Erreur \(http.statusCode)")
        } catch {
            return (false, error.localizedDescription)
        }
    }
    func adminFeedbackStats() async -> AdminFeedbackStats? {
        do {
            let res = try await adminFeedbackList(limit: 1, unreadOnly: false)
            return res.stats
        } catch {
            return nil
        }
    }
    /// Liste feedback admin (parité webapp onglet Feedback).
    func adminFeedbackList(
        limit: Int = 80,
        unreadOnly: Bool = false,
        status: String? = nil
    ) async throws -> AdminFeedbackListResponse {
        var path = "/api/admin/feedback?limit=\(max(1, min(limit, 200)))"
        if unreadOnly { path += "&unread=1" }
        if let status, !status.isEmpty {
            path += "&status=\(status.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? status)"
        }
        let (data, http, _) = try await request(path: path, method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        if http.statusCode == 403 { throw BeerAPIError.forbidden }
        guard (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(AdminFeedbackListResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded
    }
    func adminFeedbackMarkRead(id: Int, read: Bool = true) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["read": read])
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)/read",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Marquage lu impossible")
        }
    }
    func adminFeedbackReadAll() async throws {
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/read-all",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Lecture globale impossible")
        }
    }
    func adminFeedbackResolve(id: Int, status: String, reply: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "status": status,
            "reply": reply,
        ])
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)/resolve",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Réponse impossible")
        }
    }
    func adminFeedbackReopen(id: Int) async throws {
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)/reopen",
            method: "POST",
            body: Data("{}".utf8),
            contentType: "application/json"
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Réouverture impossible")
        }
    }
    func adminFeedbackDelete(id: Int) async throws {
        let (_, http, _) = try await request(
            path: "/api/admin/feedback/\(id)",
            method: "DELETE",
            body: nil
        )
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode) else {
            throw BeerAPIError.server("Suppression impossible")
        }
    }
    /// Réponses admin non vues (popup joueur).
    func feedbackReplies(unseenOnly: Bool = true) async throws -> [AdminFeedbackItem] {
        let path = "/api/feedback/replies?unseen=\(unseenOnly ? "1" : "0")&limit=20"
        let (data, http, _) = try await request(path: path, method: "GET", body: nil)
        try throwIfUnauthorized(http.statusCode)
        guard (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(FeedbackRepliesResponse.self, from: data) else {
            throw BeerAPIError.decode
        }
        return decoded.items ?? []
    }
    func markFeedbackRepliesSeen(ids: [Int]) async {
        let body = (try? JSONSerialization.data(withJSONObject: ["ids": ids])) ?? Data("{}".utf8)
        _ = try? await request(
            path: "/api/feedback/replies/seen",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
    }
}
