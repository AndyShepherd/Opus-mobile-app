import Foundation

/// Caches client data as JSON files in the Caches directory for instant loads and offline browsing.
/// Stateless enum — matches the pattern of other services (KeychainHelper, BiometricService).
///
/// Two cache layers:
/// - **Page cache**: first page of paginated results + metadata, used by ClientListView for instant startup
/// - **Full cache**: complete client list for the LogTimeView picker (backward-compatible `load()`/`save()`)
enum ClientCache {

    // MARK: - Full Cache (backward-compatible — used by LogTimeView)

    private struct CachedData: Codable {
        let customers: [Customer]
        let lastUpdated: Date
    }

    private static var fullCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clients.json")
    }

    /// Loads the full client list from cache. Used by LogTimeView for the client picker.
    static func load() -> (customers: [Customer], lastUpdated: Date)? {
        guard let data = try? Data(contentsOf: fullCacheURL),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else {
            return nil
        }
        return (cached.customers, cached.lastUpdated)
    }

    /// Saves the full client list to cache. Failures are silent — cache is best-effort.
    static func save(_ customers: [Customer]) {
        let cached = CachedData(customers: customers, lastUpdated: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fullCacheURL, options: .atomic)
    }

    // MARK: - Page Cache (used by ClientListView)

    private struct PageCacheData: Codable {
        let customers: [Customer]
        let total: Int
        let filterKey: String
        let lastUpdated: Date
    }

    private static var pageCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("clients_page1.json")
    }

    /// Loads the cached first page of clients. Returns nil if missing, corrupt, or filter key doesn't match.
    static func loadPage(filterKey: String) -> (customers: [Customer], total: Int, lastUpdated: Date)? {
        guard let data = try? Data(contentsOf: pageCacheURL),
              let cached = try? JSONDecoder().decode(PageCacheData.self, from: data),
              cached.filterKey == filterKey else {
            return nil
        }
        return (cached.customers, cached.total, cached.lastUpdated)
    }

    /// Saves page-1 results to the page cache.
    static func savePage(_ customers: [Customer], total: Int, filterKey: String) {
        let cached = PageCacheData(customers: customers, total: total, filterKey: filterKey, lastUpdated: Date())
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: pageCacheURL, options: .atomic)
    }

    // MARK: - Clear

    /// Deletes both cache files. Called on logout.
    static func clear() {
        try? FileManager.default.removeItem(at: fullCacheURL)
        try? FileManager.default.removeItem(at: pageCacheURL)
    }
}
