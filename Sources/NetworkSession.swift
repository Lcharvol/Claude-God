// NetworkSession.swift
// The URLSession every request goes through — keeps credentials off disk

import Foundation

enum NetworkSession {

    /// An ephemeral session with no URL cache. `URLSession.shared` writes each
    /// response *and its originating request* to `Cache.db`, so the usage call's
    /// `Authorization: Bearer` header — a live OAuth access token — ended up in
    /// plaintext under `~/Library/Caches` (issue #55). Nothing the app fetches
    /// benefits from caching, so no request gets one.
    static let uncached: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Files `URLCache.shared` keeps in the app's caches directory.
    private static let legacyCacheFileNames = ["Cache.db", "Cache.db-wal", "Cache.db-shm", "fsCachedData"]

    /// The on-disk URL cache left behind by versions that used
    /// `URLSession.shared`, which still holds the bearer tokens they sent.
    static func legacyCacheFiles(in cachesDirectory: URL, bundleIdentifier: String) -> [URL] {
        legacyCacheFileNames.map {
            cachesDirectory.appendingPathComponent(bundleIdentifier, isDirectory: true).appendingPathComponent($0)
        }
    }

    /// Deletes that cache. Nothing writes it any more, so this only does work
    /// on the first launch after an upgrade; later launches find no files.
    static func purgeLegacyDiskCache() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier,
              let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }

        let existing = legacyCacheFiles(in: cachesDirectory, bundleIdentifier: bundleIdentifier)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }

        existing.forEach { file in
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                Log.error("purgeLegacyDiskCache: could not delete \(file.lastPathComponent): \(error.localizedDescription)")
            }
        }
        Log.info("purgeLegacyDiskCache: removed the old URL cache (\(existing.map(\.lastPathComponent).joined(separator: ", ")))")
    }
}
