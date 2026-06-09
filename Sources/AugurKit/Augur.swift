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
    /// - Parameters:
    ///   - scope: The diff scope to assess.
    ///   - now: Reference time for recency signals.
    ///   - coverage: An optional line-coverage report; when present it sharpens
    ///     the test-gap signal per changed line.
    /// - Returns: The assessment.
    public func assess(
        scope: DiffScope,
        now: Int = Int(Date().timeIntervalSince1970),
        coverage: CoverageReport? = nil
    ) throws -> Assessment {
        let changed = try probe.changedFiles(in: scope)
        guard !changed.isEmpty else { throw AugurError.noChanges }
        let history = HistorySnapshot(commits: try probe.recentCommits(limit: historyLimit))
        return engine.assess(scope: scope, changedFiles: changed, history: history, now: now, coverage: coverage)
    }

    /// Assess a scope against a pre-built history snapshot (e.g. from a cache),
    /// skipping the `git log` walk. `now` is injectable for deterministic tests.
    /// - Parameters:
    ///   - scope: The diff scope to assess.
    ///   - history: A snapshot, typically rebuilt from a `CalibrationCache`.
    ///   - now: Reference time for recency signals.
    /// - Returns: The assessment.
    public func assess(
        scope: DiffScope,
        history: HistorySnapshot,
        now: Int = Int(Date().timeIntervalSince1970),
        coverage: CoverageReport? = nil
    ) throws -> Assessment {
        let changed = try probe.changedFiles(in: scope)
        guard !changed.isEmpty else { throw AugurError.noChanges }
        return engine.assess(scope: scope, changedFiles: changed, history: history, now: now, coverage: coverage)
    }

    /// Walks history once and returns a `CalibrationCache` pinned to the current `HEAD`.
    /// - Returns: A serializable calibration cache.
    public func calibrate() throws -> CalibrationCache {
        let commits = try probe.recentCommits(limit: historyLimit)
        let snapshot = HistorySnapshot(commits: commits)
        let head = try probe.headSHA()
        return snapshot.makeCache(head: head)
    }

    /// The current `HEAD` SHA of the underlying repository.
    /// - Returns: The SHA, or an empty string if unavailable.
    public func currentHead() throws -> String {
        try probe.headSHA()
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
