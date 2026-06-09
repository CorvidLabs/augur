@preconcurrency import Foundation

/// High-level entry point: probe a repository and produce an `Assessment`.
public struct Augur: Sendable {
    private let probe: any RepositoryProbe
    private let engine: RiskEngine
    private let historyLimit: Int

    public init(
        probe: any RepositoryProbe,
        engine: RiskEngine = RiskEngine(),
        historyLimit: Int = 500
    ) {
        self.probe = probe
        self.engine = engine
        self.historyLimit = historyLimit
    }

    /// Assess a scope. `now` is injectable for deterministic tests.
    public func assess(scope: DiffScope, now: Int = Int(Date().timeIntervalSince1970)) throws -> Assessment {
        let changed = try probe.changedFiles(in: scope)
        guard !changed.isEmpty else { throw AugurError.noChanges }
        let history = HistorySnapshot(commits: try probe.recentCommits(limit: historyLimit))
        return engine.assess(scope: scope, changedFiles: changed, history: history, now: now)
    }
}

// MARK: - JSON

extension Assessment {
    /// Stable, agent-friendly JSON. Keys are ordered for readable diffs.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}
