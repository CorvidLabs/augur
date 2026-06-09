@preconcurrency import Foundation

// MARK: - Diff Scope

/// The unit of change `augur` assesses.
///
/// `augur` is range-first: a commit range is the native input, and the working
/// tree / staged index are expressed as ranges against `HEAD`.
public enum DiffScope: Sendable, Equatable {
    /// An explicit git range, e.g. `main..HEAD`.
    case range(String)
    /// Staged changes (`git diff --cached`).
    case staged
    /// Unstaged + staged working-tree changes against `HEAD`.
    case workingTree

    /// A short label for human and JSON output.
    public var label: String {
        switch self {
        case .range(let value): return value
        case .staged: return "staged"
        case .workingTree: return "working-tree"
        }
    }
}

// MARK: - Change Surface

/// A single file touched by the change under assessment.
public struct ChangedFile: Sendable, Equatable, Codable {
    public let path: String
    public let linesAdded: Int
    public let linesDeleted: Int
    public let isBinary: Bool

    public init(path: String, linesAdded: Int, linesDeleted: Int, isBinary: Bool) {
        self.path = path
        self.linesAdded = linesAdded
        self.linesDeleted = linesDeleted
        self.isBinary = isBinary
    }

    /// Total lines touched (additions + deletions).
    public var churnLines: Int { linesAdded + linesDeleted }
}

/// A historical commit, used to derive churn, ownership, coupling, and incidents.
public struct Commit: Sendable, Equatable, Codable {
    public let hash: String
    public let authorEmail: String
    public let timestamp: Int
    public let subject: String
    public let files: [String]

    public init(hash: String, authorEmail: String, timestamp: Int, subject: String, files: [String]) {
        self.hash = hash
        self.authorEmail = authorEmail
        self.timestamp = timestamp
        self.subject = subject
        self.files = files
    }
}

// MARK: - Signals

/// One deterministic risk contribution for a file.
///
/// `risk` is normalized to `0...1` (0 = safe, 1 = maximally risky) and is the
/// value combined by the engine; `weight` is the signal's share of the blend;
/// `detail` is a human-readable justification.
public struct Signal: Sendable, Equatable, Codable {
    public let name: String
    public let risk: Double
    public let weight: Double
    public let detail: String

    public init(name: String, risk: Double, weight: Double, detail: String) {
        self.name = name
        self.risk = max(0, min(1, risk))
        self.weight = weight
        self.detail = detail
    }
}

// MARK: - Verdict

/// The action `augur` recommends for a change.
public enum Verdict: String, Sendable, Codable, CaseIterable, Comparable {
    /// Low risk: safe for an agent to proceed / a human to fast-track.
    case proceed
    /// Elevated risk: an agent should ask for human review.
    case review
    /// High risk: should not merge without deliberate human sign-off.
    case block

    private var order: Int {
        switch self {
        case .proceed: return 0
        case .review: return 1
        case .block: return 2
        }
    }

    public static func < (lhs: Verdict, rhs: Verdict) -> Bool {
        lhs.order < rhs.order
    }

    /// Maps an overall risk score (0...100) to a verdict using the default thresholds.
    public static func from(riskScore: Double) -> Verdict {
        from(riskScore: riskScore, thresholds: .default)
    }

    /// Maps an overall risk score (0...100) to a verdict using explicit thresholds.
    /// - Parameters:
    ///   - riskScore: The blended risk score in `0...100`.
    ///   - thresholds: The review/block cutoffs to apply.
    /// - Returns: The recommended verdict.
    public static func from(riskScore: Double, thresholds: Thresholds) -> Verdict {
        if riskScore >= thresholds.block { return .block }
        if riskScore >= thresholds.review { return .review }
        return .proceed
    }
}

// MARK: - Thresholds

/// Configurable risk-score cutoffs that map a score (0...100) to a `Verdict`.
///
/// A score `>= block` blocks; `>= review` (but below `block`) requests review;
/// anything lower proceeds. The defaults (`35` / `65`) match `augur`'s original
/// hard-coded mapping, so omitting configuration is behavior-preserving.
public struct Thresholds: Sendable, Equatable, Codable {
    /// Scores at or above this require at least `review`.
    public let review: Double
    /// Scores at or above this `block`.
    public let block: Double

    /// The historical default cutoffs (`review: 35`, `block: 65`).
    public static let `default` = Thresholds(review: 35, block: 65)

    /// Creates a threshold pair. `review` is clamped to be no greater than `block`.
    /// - Parameters:
    ///   - review: The review cutoff (0...100).
    ///   - block: The block cutoff (0...100).
    public init(review: Double, block: Double) {
        let safeBlock = max(0, min(100, block))
        self.block = safeBlock
        self.review = max(0, min(safeBlock, review))
    }
}

// MARK: - Assessments

/// Per-file risk assessment with its contributing signals.
public struct FileAssessment: Sendable, Equatable, Codable {
    public let path: String
    public let riskScore: Double
    public let signals: [Signal]

    public init(path: String, riskScore: Double, signals: [Signal]) {
        self.path = path
        self.riskScore = riskScore
        self.signals = signals
    }

    /// Inverse of risk: how confident `augur` is that the file is safe (0...100).
    public var confidence: Double { 100 - riskScore }

    /// The file's verdict under the default thresholds. For verdicts under
    /// configured thresholds, use `verdict(thresholds:)`.
    public var verdict: Verdict { Verdict.from(riskScore: riskScore) }

    /// The file's verdict under the given thresholds.
    /// - Parameter thresholds: The cutoffs to apply.
    /// - Returns: The recommended verdict for this file.
    public func verdict(thresholds: Thresholds) -> Verdict {
        Verdict.from(riskScore: riskScore, thresholds: thresholds)
    }
}

/// How much the score is backed by the repository's own history.
///
/// The heuristic prior always applies; calibration *adjusts* it using the
/// repo's revert / hotfix record. This field tells consumers whether a score is
/// "prior only" or "history-backed", so an agent can weight the verdict.
public struct Calibration: Sendable, Equatable, Codable {
    public let confidence: Double
    public let totalCommits: Int
    public let incidentCommits: Int

    public init(confidence: Double, totalCommits: Int, incidentCommits: Int) {
        self.confidence = max(0, min(1, confidence))
        self.totalCommits = totalCommits
        self.incidentCommits = incidentCommits
    }

    public var band: String {
        switch confidence {
        case ..<0.25: return "prior-only"
        case ..<0.6: return "weak"
        default: return "history-backed"
        }
    }
}

/// The top-level result of an assessment.
public struct Assessment: Sendable, Equatable, Codable {
    public let scope: String
    public let riskScore: Double
    public let verdict: Verdict
    public let calibration: Calibration
    public let thresholds: Thresholds
    public let files: [FileAssessment]

    public init(
        scope: String,
        riskScore: Double,
        verdict: Verdict,
        calibration: Calibration,
        thresholds: Thresholds = .default,
        files: [FileAssessment]
    ) {
        self.scope = scope
        self.riskScore = riskScore
        self.verdict = verdict
        self.calibration = calibration
        self.thresholds = thresholds
        self.files = files
    }

    public var confidence: Double { 100 - riskScore }
}

// MARK: - Errors

public enum AugurError: Error, LocalizedError, Sendable {
    case notARepository(String)
    case git(command: String, status: Int32)
    case noChanges

    public var errorDescription: String? {
        switch self {
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        case .git(let command, let status):
            return "git \(command) failed (exit \(status))"
        case .noChanges:
            return "No changes found in the requested scope."
        }
    }
}
