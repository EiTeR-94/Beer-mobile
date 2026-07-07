import Foundation

/// Central NetworkManager (partial extraction for priority 3).
/// Handles common retry, base URL concerns and can be expanded.
/// Currently wraps the existing retry logic and provides helpers.
/// Goal: reduce duplication in BeerAPI/AppModel and prepare for full service split (priority 1).
@MainActor
final class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

    /// Reusable exponential backoff retry (used by download, can be used for other calls).
    func withRetry<T>(maxAttempts: Int = 3, baseDelayMs: UInt64 = 300, _ op: () async throws -> T) async throws -> T {
        var attempt = 0
        var lastErr: Error?
        while attempt < maxAttempts {
            do {
                return try await op()
            } catch {
                lastErr = error
                attempt += 1
                if attempt >= maxAttempts { break }
                let delay = baseDelayMs * UInt64(1 << (attempt - 1))
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
            }
        }
        throw lastErr ?? BeerAPIError.network(NSError(domain: "NetworkManager", code: -1))
    }

    // Future: central discover, health, etc. to reduce god object in AppModel.
    // For now, delegates to BeerAPI for transport.
}