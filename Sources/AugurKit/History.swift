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

    // MARK: - Queries

    public func churnCount(_ file: String) -> Int { churn[file] ?? 0 }

    public func authorCount(_ file: String) -> Int { authors[file]?.count ?? 0 }

    public func isIncidentProne(_ file: String) -> Bool { incidentFiles.contains(file) }

    public func daysSinceTouched(_ file: String, now: Int) -> Int? {
        guard let last = lastTouched[file] else { return nil }
        return max(0, (now - last) / 86_400)
    }

    /// The historically strongest co-change partner of `file` and its count.
    public func topPartner(_ file: String) -> (partner: String, count: Int)? {
        guard let partners = coChange[file] else { return nil }
        guard let best = partners.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }

    static func looksLikeIncident(_ subject: String) -> Bool {
        let lower = subject.lowercased()
        if lower.hasPrefix("revert") || lower.hasPrefix("fixup") { return true }
        if lower.hasPrefix("fix:") || lower.hasPrefix("fix(") || lower.hasPrefix("hotfix") { return true }
        return lower.contains("revert \"") || lower.contains("emergency")
    }
}
