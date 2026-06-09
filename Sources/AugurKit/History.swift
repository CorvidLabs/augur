@preconcurrency import Foundation

/// Derived, query-friendly view over recent commits.
///
/// Built once from a single `git log` so signals are pure functions over it.
public struct HistorySnapshot: Sendable {
    public let totalCommits: Int
    public let incidentCommits: Int

    /// Number of commits each file appears in.
    private let churn: [String: Int]
    /// Most recent commit timestamp per file.
    private let lastTouched: [String: Int]
    /// Distinct author emails per file.
    private let authors: [String: Set<String>]
    /// Co-change counts: for a file, how often each other file changed with it.
    private let coChange: [String: [String: Int]]
    /// Files implicated in revert / hotfix / fix-follow-up commits.
    private let incidentFiles: Set<String>

    /// Rebuilds a snapshot directly from a previously computed `CalibrationCache`,
    /// avoiding a fresh `git log` walk. The reconstructed snapshot answers every
    /// query identically to one derived from the original commits.
    /// - Parameter cache: A serialized projection of a prior snapshot.
    public init(cache: CalibrationCache) {
        self.totalCommits = cache.totalCommits
        self.incidentCommits = cache.incidentCommits
        self.churn = cache.churn
        self.lastTouched = cache.lastTouched
        self.authors = cache.authors.mapValues { Set($0) }
        self.coChange = cache.coChange
        self.incidentFiles = Set(cache.incidentFiles)
    }

    public init(commits: [Commit]) {
        var churn: [String: Int] = [:]
        var lastTouched: [String: Int] = [:]
        var authors: [String: Set<String>] = [:]
        var coChange: [String: [String: Int]] = [:]
        var incidentFiles: Set<String> = []
        var incidentCommits = 0

        for commit in commits {
            let isIncident = Self.looksLikeIncident(commit.subject)
            if isIncident { incidentCommits += 1 }
            for file in commit.files {
                churn[file, default: 0] += 1
                if commit.timestamp > (lastTouched[file] ?? 0) {
                    lastTouched[file] = commit.timestamp
                }
                authors[file, default: []].insert(commit.authorEmail)
                if isIncident { incidentFiles.insert(file) }
            }
            // Co-change pairs within the commit.
            if commit.files.count > 1 {
                for file in commit.files {
                    for other in commit.files where other != file {
                        coChange[file, default: [:]][other, default: 0] += 1
                    }
                }
            }
        }

        self.totalCommits = commits.count
        self.incidentCommits = incidentCommits
        self.churn = churn
        self.lastTouched = lastTouched
        self.authors = authors
        self.coChange = coChange
        self.incidentFiles = incidentFiles
    }

    // MARK: - Caching

    /// Produces a serializable projection of this snapshot for caching.
    ///
    /// The projection captures exactly the facts the engine queries, so a
    /// snapshot rebuilt from it via `init(cache:)` scores identically.
    /// - Parameter head: The repository `HEAD` SHA at calibration time.
    /// - Returns: A `Codable` cache pinned to `head`.
    public func makeCache(head: String) -> CalibrationCache {
        CalibrationCache(
            head: head,
            totalCommits: totalCommits,
            incidentCommits: incidentCommits,
            churn: churn,
            lastTouched: lastTouched,
            authors: authors.mapValues { Array($0).sorted() },
            coChange: coChange,
            incidentFiles: Array(incidentFiles).sorted()
        )
    }

    // MARK: - Queries

    public func churnCount(_ file: String) -> Int { churn[file] ?? 0 }

    public func authorCount(_ file: String) -> Int { authors[file]?.count ?? 0 }

    public func isIncidentProne(_ file: String) -> Bool { incidentFiles.contains(file) }

    /// Days since `file` was last touched, relative to `now`, or `nil` if the file
    /// has no history. Recency data is derived but no current signal scores it, so
    /// this is exposed for callers and reserved for a future time-based signal; it
    /// does not affect the verdict.
    public func daysSinceTouched(_ file: String, now: Int) -> Int? {
        guard let last = lastTouched[file] else { return nil }
        return max(0, (now - last) / 86_400)
    }

    /// The historically strongest co-change partner of `file` and its count.
    ///
    /// Ties on count are broken by partner path (ascending) so the result is
    /// deterministic regardless of dictionary iteration order.
    public func topPartner(_ file: String) -> (partner: String, count: Int)? {
        guard let partners = coChange[file] else { return nil }
        let best = partners.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }
        guard let best else { return nil }
        return (best.key, best.value)
    }

    static func looksLikeIncident(_ subject: String) -> Bool {
        let lower = subject.lowercased()
        if lower.hasPrefix("revert") || lower.hasPrefix("fixup") { return true }
        if lower.hasPrefix("fix:") || lower.hasPrefix("fix(") || lower.hasPrefix("hotfix") { return true }
        return lower.contains("revert \"") || lower.contains("emergency")
    }
}

// MARK: - Calibration Cache

/// A serializable projection of a `HistorySnapshot`, pinned to a `HEAD` SHA.
///
/// `augur calibrate` writes this to `.augur/cache.json` so a later `check --cached`
/// can rebuild an equivalent snapshot via `HistorySnapshot(cache:)` without walking
/// `git log` again. A mismatch between `head` and the current `HEAD` signals staleness.
public struct CalibrationCache: Sendable, Equatable, Codable {
    /// The repository `HEAD` SHA when the cache was written.
    public let head: String
    /// Total commits walked during calibration.
    public let totalCommits: Int
    /// Commits whose subject looked like an incident (revert/hotfix/fix).
    public let incidentCommits: Int
    /// Number of commits each file appears in.
    public let churn: [String: Int]
    /// Most recent commit timestamp per file.
    public let lastTouched: [String: Int]
    /// Distinct author emails per file (sorted for stable output).
    public let authors: [String: [String]]
    /// Co-change counts: for a file, how often each other file changed with it.
    public let coChange: [String: [String: Int]]
    /// Files implicated in revert / hotfix commits (sorted for stable output).
    public let incidentFiles: [String]

    public init(
        head: String,
        totalCommits: Int,
        incidentCommits: Int,
        churn: [String: Int],
        lastTouched: [String: Int],
        authors: [String: [String]],
        coChange: [String: [String: Int]],
        incidentFiles: [String]
    ) {
        self.head = head
        self.totalCommits = totalCommits
        self.incidentCommits = incidentCommits
        self.churn = churn
        self.lastTouched = lastTouched
        self.authors = authors
        self.coChange = coChange
        self.incidentFiles = incidentFiles
    }

    /// The calibration confidence implied by this cache's volume and incidents.
    public var confidence: Double {
        RiskEngine.calibrationConfidence(totalCommits: totalCommits, incidentCommits: incidentCommits)
    }

    /// The calibration band (`prior-only` / `weak` / `history-backed`).
    public var band: String {
        Calibration(confidence: confidence, totalCommits: totalCommits, incidentCommits: incidentCommits).band
    }

    /// Decodes a cache from JSON `Data`.
    /// - Parameter data: UTF-8 JSON produced by `jsonData()`.
    /// - Returns: The decoded cache.
    public static func decoded(from data: Data) throws -> CalibrationCache {
        try JSONDecoder().decode(CalibrationCache.self, from: data)
    }

    /// Encodes the cache as stable, sorted-key JSON.
    /// - Returns: UTF-8 JSON `Data`.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
