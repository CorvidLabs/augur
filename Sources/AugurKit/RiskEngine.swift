@preconcurrency import Foundation

/// Blends deterministic signals into a per-file and overall risk verdict.
///
/// The engine has two layers:
///  1. a transparent **heuristic prior** (documented weights), which always applies; and
///  2. a **history calibration** that scales the incident signal by how much the
///     repository's own revert/hotfix record backs it.
public struct RiskEngine: Sendable {
    /// Documented prior weights for each signal. Sum to 1.0.
    public struct Weights: Sendable, Equatable, Codable {
        public var sensitivity = 0.22
        public var testGap = 0.18
        public var churn = 0.15
        public var coupling = 0.13
        public var diffShape = 0.12
        public var ownership = 0.10
        public var incident = 0.10

        public init() {}
    }

    private let weights: Weights
    private let rules: [SensitivityRule]
    private let thresholds: Thresholds

    /// Constructs the engine.
    /// - Parameters:
    ///   - weights: Prior weights for each signal (sum to 1.0).
    ///   - rules: Sensitivity rules matched against changed paths.
    ///   - thresholds: Risk-score cutoffs mapping a score to a `Verdict`.
    public init(
        weights: Weights = Weights(),
        rules: [SensitivityRule] = SensitivityRuleset.default,
        thresholds: Thresholds = .default
    ) {
        self.weights = weights
        self.rules = rules
        self.thresholds = thresholds
    }

    // MARK: - Assessment

    public func assess(
        scope: DiffScope,
        changedFiles: [ChangedFile],
        history: HistorySnapshot,
        now: Int,
        coverage: CoverageReport? = nil,
        excludedPaths: [String] = []
    ) -> Assessment {
        let calibration = Calibration(
            confidence: Self.calibrationConfidence(totalCommits: history.totalCommits, incidentCommits: history.incidentCommits),
            totalCommits: history.totalCommits,
            incidentCommits: history.incidentCommits
        )

        let changedPaths = Set(changedFiles.map(\.path))
        let touchedTests = changedFiles.contains { TestHeuristics.isTestFile($0.path) }

        let files = changedFiles.map { file in
            assessFile(
                file,
                history: history,
                changedPaths: changedPaths,
                touchedTests: touchedTests,
                calibration: calibration,
                coverage: coverage,
                now: now
            )
        }

        let overall = Self.aggregate(files: files)
        var verdict = Verdict.from(riskScore: overall, thresholds: thresholds)
        // A single very-hot file escalates the whole change.
        if let worst = files.map(\.riskScore).max(), worst >= 80 {
            verdict = max(verdict, .block)
        }

        return Assessment(
            scope: scope.label,
            riskScore: overall,
            verdict: verdict,
            calibration: calibration,
            thresholds: thresholds,
            files: files.sorted { $0.riskScore > $1.riskScore },
            excludedPaths: excludedPaths.sorted()
        )
    }

    // MARK: - Per-file signals

    private func assessFile(
        _ file: ChangedFile,
        history: HistorySnapshot,
        changedPaths: Set<String>,
        touchedTests: Bool,
        calibration: Calibration,
        coverage: CoverageReport?,
        now: Int
    ) -> FileAssessment {
        var signals: [Signal] = []

        // Sensitivity.
        if let rule = SensitivityRuleset.match(file.path, rules: rules) {
            signals.append(Signal(name: "sensitivity", risk: rule.risk, weight: weights.sensitivity, detail: "matches sensitive category '\(rule.label)'"))
        } else {
            signals.append(Signal(name: "sensitivity", risk: 0, weight: weights.sensitivity, detail: "no sensitive paths"))
        }

        // Test gap. When a coverage report is supplied, the signal becomes precise
        // for non-test code files: it scores the uncovered fraction of the change's
        // instrumented added lines. Without coverage, the original heuristic applies.
        let isTest = TestHeuristics.isTestFile(file.path)
        if isTest {
            signals.append(Signal(name: "test-gap", risk: 0, weight: weights.testGap, detail: "file is a test"))
        } else if file.isBinary {
            signals.append(Signal(name: "test-gap", risk: 0.1, weight: weights.testGap, detail: "binary asset, not unit-testable"))
        } else if let coverage, let signal = Self.coverageTestGap(file: file, coverage: coverage, weight: weights.testGap) {
            signals.append(signal)
        } else if touchedTests {
            signals.append(Signal(name: "test-gap", risk: 0.15, weight: weights.testGap, detail: "tests changed alongside"))
        } else {
            signals.append(Signal(name: "test-gap", risk: 0.7, weight: weights.testGap, detail: "code changed with no test in the changeset"))
        }

        // Churn: hot files are fragile.
        let churn = history.churnCount(file.path)
        let churnRisk = min(1, Double(churn) / 40)
        signals.append(Signal(name: "churn", risk: churnRisk, weight: weights.churn, detail: "\(churn) recent commits touched this file"))

        // Coupling anomaly: a strong historical partner is absent from the change.
        if let partner = history.topPartner(file.path), partner.count >= 4, !changedPaths.contains(partner.partner) {
            signals.append(Signal(name: "coupling", risk: 0.6, weight: weights.coupling, detail: "usually changes with '\(partner.partner)' (\(partner.count)x), which is absent"))
        } else {
            signals.append(Signal(name: "coupling", risk: 0, weight: weights.coupling, detail: "no broken co-change pattern"))
        }

        // Diff shape: large single-file edits are harder to review.
        let diffRisk = file.isBinary ? 0.2 : min(1, Double(file.churnLines) / 400)
        signals.append(Signal(name: "diff-shape", risk: diffRisk, weight: weights.diffShape, detail: "\(file.churnLines) lines touched"))

        // Ownership: U-shaped — both diffuse ownership and bus-factor are risky.
        let authors = history.authorCount(file.path)
        let ownershipRisk: Double
        let ownershipDetail: String
        switch authors {
        case 0: ownershipRisk = 0.3; ownershipDetail = "new/untracked file"
        case 1: ownershipRisk = 0.35; ownershipDetail = "single author (bus-factor)"
        case 2...4: ownershipRisk = 0.1; ownershipDetail = "\(authors) authors"
        default: ownershipRisk = 0.6; ownershipDetail = "\(authors) authors (diffuse ownership)"
        }
        signals.append(Signal(name: "ownership", risk: ownershipRisk, weight: weights.ownership, detail: ownershipDetail))

        // Incident proneness (calibrated): scaled by how much history backs it.
        let incidentBase = history.isIncidentProne(file.path) ? 0.8 : 0.0
        let incidentRisk = incidentBase * calibration.confidence
        let incidentDetail = history.isIncidentProne(file.path)
            ? "implicated in past reverts/hotfixes (calibration \(String(format: "%.2f", calibration.confidence)))"
            : "no incident history"
        signals.append(Signal(name: "incident", risk: incidentRisk, weight: weights.incident, detail: incidentDetail))

        let score = Self.weightedScore(signals)
        return FileAssessment(path: file.path, riskScore: score, signals: signals)
    }

    // MARK: - Coverage test-gap

    /// The coverage-derived test-gap signal for a non-test, non-binary code file,
    /// or `nil` when coverage can't refine it (so the heuristic should apply).
    ///
    /// Behavior:
    ///  - File absent from the report → high risk (`0.7`), "not in coverage report".
    ///  - File present with instrumented changed lines →
    ///    `risk = 1 - (covered / instrumented)`.
    ///  - File present but no changed line was instrumented, or no added lines are
    ///    known → `nil` (fall back to heuristic).
    static func coverageTestGap(file: ChangedFile, coverage: CoverageReport, weight: Double) -> Signal? {
        // Without per-line data we cannot be precise; let the heuristic decide.
        guard !file.addedLines.isEmpty else {
            // The file may still be entirely absent from coverage (uncovered).
            if coverage.matchFile(diffPath: file.path) == nil {
                return Signal(name: "test-gap", risk: 0.7, weight: weight, detail: "not in coverage report")
            }
            return nil
        }
        let result = coverage.query(path: file.path, changedLines: file.addedLines)
        guard result.fileMatched else {
            return Signal(name: "test-gap", risk: 0.7, weight: weight, detail: "not in coverage report")
        }
        guard let fraction = result.coveredFraction else {
            // Matched, but no changed line was instrumented — nothing to measure.
            return nil
        }
        let percent = Int((fraction * 100).rounded())
        return Signal(
            name: "test-gap",
            risk: 1 - fraction,
            weight: weight,
            detail: "\(result.covered)/\(result.instrumented) changed lines covered (\(percent)%)"
        )
    }

    // MARK: - Math

    static func weightedScore(_ signals: [Signal]) -> Double {
        let totalWeight = signals.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 0 }
        let weighted = signals.reduce(0) { $0 + $1.risk * $1.weight }
        return (weighted / totalWeight) * 100
    }

    static func aggregate(files: [FileAssessment]) -> Double {
        guard !files.isEmpty else { return 0 }
        let risks = files.map(\.riskScore)
        let maxRisk = risks.max() ?? 0
        let mean = risks.reduce(0, +) / Double(risks.count)
        // Breadth: many files is itself a review burden.
        let breadth = min(15, Double(files.count - 1) * 1.0)
        return min(100, 0.65 * maxRisk + 0.35 * mean + breadth)
    }

    /// Calibration confidence grows with history volume; incident commits sharpen it.
    static func calibrationConfidence(totalCommits: Int, incidentCommits: Int) -> Double {
        let volume = min(1.0, Double(totalCommits) / 300.0)
        let signal = min(1.0, Double(incidentCommits) / 25.0)
        // Depth of history gates confidence; incident signal sharpens it within that gate.
        return volume * (0.4 + 0.6 * signal)
    }
}
