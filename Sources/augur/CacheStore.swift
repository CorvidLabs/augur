@preconcurrency import Foundation
import AugurKit

// MARK: - Cache Store

/// Reads and writes the local calibration cache at `.augur/cache.json`.
///
/// The cache is repo-local and never committed (`.augur/` is git-ignored); it
/// simply lets `check --cached` skip re-walking `git log`.
enum CacheStore {
    /// The cache directory name at the repository root.
    static let directoryName = ".augur"
    /// The cache filename inside `directoryName`.
    static let fileName = "cache.json"

    /// The absolute-or-relative path to the cache file for a given repo root.
    static func path(repoPath: String) -> String {
        let directory = (repoPath as NSString).appendingPathComponent(directoryName)
        return (directory as NSString).appendingPathComponent(fileName)
    }

    /// Writes the cache, creating `.augur/` if needed.
    static func save(_ cache: CalibrationCache, repoPath: String) throws {
        let directory = (repoPath as NSString).appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try cache.jsonData().write(to: URL(fileURLWithPath: path(repoPath: repoPath)))
    }

    /// Loads the cache, returning `nil` if it is absent or unreadable.
    static func load(repoPath: String) -> CalibrationCache? {
        guard let data = FileManager.default.contents(atPath: path(repoPath: repoPath)) else { return nil }
        return try? CalibrationCache.decoded(from: data)
    }
}

// MARK: - Diagnostics

/// Stderr messaging so notes and warnings never pollute stdout (which carries
/// JSON / the report a caller may pipe).
enum Diagnostics {
    /// Writes a one-line `augur:` note to stderr.
    static func note(_ message: String) {
        FileHandle.standardError.write(Data("augur: \(message)\n".utf8))
    }

    /// Writes a one-line `augur: warning:` message to stderr (non-fatal).
    static func warn(_ message: String) {
        FileHandle.standardError.write(Data("augur: warning: \(message)\n".utf8))
    }
}
