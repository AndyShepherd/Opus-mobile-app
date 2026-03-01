import Foundation

/// Caches client data as a JSON file in the Caches directory for instant loads and offline browsing.
/// Stateless enum — matches the pattern of other services (KeychainHelper, BiometricService).
enum ClientCache {

    private struct CachedData: Codable {
        let customers: [Customer]
        let lastUpdated: Date
    }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clients.json")
    }

    /// Loads cached clients and the timestamp they were saved. Returns nil if missing or corrupt.
    static func load() -> (customers: [Customer], lastUpdated: Date)? {
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        return (cached.customers, cached.lastUpdated)
    }

    /// Saves clients to the cache file. Failures are silent — cache is best-effort.
    static func save(_ customers: [Customer]) {
        let cached = CachedData(customers: customers, lastUpdated: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    /// Deletes the cache file. Called on logout.
    static func clear() {
        try? FileManager.default.removeItem(at: cacheURL)
    }
}
