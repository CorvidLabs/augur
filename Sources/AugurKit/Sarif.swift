@preconcurrency import Foundation

// MARK: - SARIF Report

/// A minimal, valid [SARIF 2.1.0](https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html)
/// document projecting an `Assessment` into a static-analysis log that GitHub code
/// scanning (and other SARIF consumers) can ingest to annotate a pull request inline.
///
/// The model is intentionally a *subset* of the full SARIF schema — just enough to
/// emit one `run` carrying one `result` per assessed file. It is Foundation-only
/// (`Codable`), so `AugurKit` keeps its zero-third-party-dependency contract.
///
/// ## Rule modeling
///
/// augur emits a **single** reporting descriptor, `augur/change-risk`, rather than
/// one rule per signal. Each `result` then attributes the verdict to that rule and
/// summarizes the *contributing signals* in its `message.text`. This keeps the rule
/// catalog stable across releases (signals can be added without minting new rule
/// IDs) and matches augur's model: the verdict is the unit of risk, signals explain it.
///
/// ## Level mapping
///
/// A file's `Verdict` maps to a SARIF result `level`:
/// - `block` → `error`
/// - `review` → `warning`
/// - `proceed` → `note`
public struct SarifReport: Sendable, Equatable, Codable {
    /// The SARIF schema URI for the version emitted.
    public let schema: String
    /// The SARIF format version. Always `"2.1.0"`.
    public let version: String
    /// The analysis runs in the log. augur always emits exactly one.
    public let runs: [Run]

    private enum CodingKeys: String, CodingKey {
        case schema = "$schema"
        case version
        case runs
    }

    /// Constructs a report from explicit parts. Prefer `init(from:)` to project an
    /// `Assessment`.
    public init(schema: String, version: String, runs: [Run]) {
        self.schema = schema
        self.version = version
        self.runs = runs
    }

    // MARK: - Constants

    /// The SARIF 2.1.0 JSON schema URL emitted in `$schema`.
    public static let schemaURL =
        "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json"

    /// The SARIF format version augur emits.
    public static let sarifVersion = "2.1.0"

    /// augur's project home, emitted as the tool driver `informationUri`.
    public static let informationURI = "https://github.com/CorvidLabs/augur"

    /// The stable id of the single reporting descriptor augur emits.
    public static let ruleID = "augur/change-risk"

    // MARK: - Run

    /// A single SARIF analysis run produced by one tool invocation.
    public struct Run: Sendable, Equatable, Codable {
        /// The analysis tool that produced the run.
        public let tool: Tool
        /// One result per assessed file.
        public let results: [Result]

        public init(tool: Tool, results: [Result]) {
            self.tool = tool
            self.results = results
        }
    }

    // MARK: - Tool

    /// The tool component wrapper required by SARIF (`tool.driver`).
    public struct Tool: Sendable, Equatable, Codable {
        /// The primary tool component that produced the analysis.
        public let driver: Driver

        public init(driver: Driver) {
            self.driver = driver
        }
    }

    /// The driver component describing augur and its rule catalog.
    public struct Driver: Sendable, Equatable, Codable {
        /// The tool name (`"augur"`).
        public let name: String
        /// A link to augur's project home.
        public let informationUri: String
        /// augur's semantic version, e.g. `"0.2.0"`.
        public let semanticVersion: String
        /// The reporting descriptors (rules) this run can reference.
        public let rules: [ReportingDescriptor]

        public init(name: String, informationUri: String, semanticVersion: String, rules: [ReportingDescriptor]) {
            self.name = name
            self.informationUri = informationUri
            self.semanticVersion = semanticVersion
            self.rules = rules
        }
    }

    // MARK: - Reporting Descriptor (rule)

    /// A SARIF reporting descriptor — the metadata for a rule a result can cite.
    public struct ReportingDescriptor: Sendable, Equatable, Codable {
        /// The stable rule id (`augur/change-risk`).
        public let id: String
        /// A short, human-readable rule name.
        public let name: String
        /// A one-line description of what the rule reports.
        public let shortDescription: Message
        /// A link to documentation for the rule.
        public let helpUri: String

        public init(id: String, name: String, shortDescription: Message, helpUri: String) {
            self.id = id
            self.name = name
            self.shortDescription = shortDescription
            self.helpUri = helpUri
        }
    }

    // MARK: - Result

    /// One SARIF result: an assessed file's verdict, severity, and location.
    public struct Result: Sendable, Equatable, Codable {
        /// The id of the rule this result cites (`augur/change-risk`).
        public let ruleId: String
        /// The SARIF severity: `error`, `warning`, or `note`.
        public let level: Level
        /// A human-readable summary of the verdict and its top signals.
        public let message: Message
        /// Where the result applies. augur emits exactly one location per result.
        public let locations: [Location]
        /// augur-specific facts (`riskScore`, `confidence`, `verdict`).
        public let properties: Properties

        public init(ruleId: String, level: Level, message: Message, locations: [Location], properties: Properties) {
            self.ruleId = ruleId
            self.level = level
            self.message = message
            self.locations = locations
            self.properties = properties
        }
    }

    // MARK: - Level

    /// SARIF result severity. Mapped from `Verdict`.
    public enum Level: String, Sendable, Equatable, Codable {
        /// Maps from `Verdict.block`.
        case error
        /// Maps from `Verdict.review`.
        case warning
        /// Maps from `Verdict.proceed`.
        case note

        /// The SARIF level for a verdict: `block → error`, `review → warning`,
        /// `proceed → note`.
        /// - Parameter verdict: The file's verdict.
        /// - Returns: The corresponding SARIF level.
        public static func from(verdict: Verdict) -> Level {
            switch verdict {
            case .block: return .error
            case .review: return .warning
            case .proceed: return .note
            }
        }
    }

    // MARK: - Message

    /// A SARIF message with plain text.
    public struct Message: Sendable, Equatable, Codable {
        /// The message text.
        public let text: String

        public init(text: String) {
            self.text = text
        }
    }

    // MARK: - Location

    /// A SARIF location wrapping a physical location.
    public struct Location: Sendable, Equatable, Codable {
        /// The physical (file + region) location.
        public let physicalLocation: PhysicalLocation

        public init(physicalLocation: PhysicalLocation) {
            self.physicalLocation = physicalLocation
        }
    }

    /// A physical location: an artifact (file) and an optional region within it.
    public struct PhysicalLocation: Sendable, Equatable, Codable {
        /// The file the result applies to.
        public let artifactLocation: ArtifactLocation
        /// The line region, when an added line is known; otherwise `nil` (the whole file).
        public let region: Region?

        public init(artifactLocation: ArtifactLocation, region: Region?) {
            self.artifactLocation = artifactLocation
            self.region = region
        }
    }

    /// A reference to a file by its repo-relative URI.
    public struct ArtifactLocation: Sendable, Equatable, Codable {
        /// The repo-relative file path.
        public let uri: String

        public init(uri: String) {
            self.uri = uri
        }
    }

    /// A line region within an artifact. Lines are 1-based.
    public struct Region: Sendable, Equatable, Codable {
        /// The 1-based start line.
        public let startLine: Int

        public init(startLine: Int) {
            self.startLine = startLine
        }
    }

    // MARK: - Properties

    /// augur-specific facts carried in `result.properties`.
    public struct Properties: Sendable, Equatable, Codable {
        /// The file's risk score (0...100).
        public let riskScore: Double
        /// The file's confidence (`100 - riskScore`).
        public let confidence: Double
        /// The file's verdict raw value.
        public let verdict: String

        public init(riskScore: Double, confidence: Double, verdict: String) {
            self.riskScore = riskScore
            self.confidence = confidence
            self.verdict = verdict
        }
    }
}

// MARK: - Builder

extension SarifReport {
    /// Projects an `Assessment` into a SARIF 2.1.0 report.
    ///
    /// Emits one `run` whose driver is augur (carrying the single `augur/change-risk`
    /// rule) and one `result` per file in the assessment, in the assessment's order.
    /// Each result's `level` is mapped from the file's verdict under the assessment's
    /// thresholds; its `region.startLine` is the file's first added line when
    /// `addedLines` is non-empty, otherwise the region is omitted.
    /// - Parameters:
    ///   - assessment: The assessment to project.
    ///   - toolVersion: augur's semantic version (the CLI passes its own version).
    ///   - addedLinesByPath: First added line per file path, used to populate
    ///     `region.startLine`. Paths absent here (or with no added lines) get no region.
    public init(
        from assessment: Assessment,
        toolVersion: String,
        addedLinesByPath: [String: [Int]] = [:]
    ) {
        let rule = ReportingDescriptor(
            id: Self.ruleID,
            name: "ChangeRisk",
            shortDescription: Message(
                text: "Deterministic change-risk verdict (proceed/review/block) from structural git signals."
            ),
            helpUri: Self.informationURI
        )
        let driver = Driver(
            name: "augur",
            informationUri: Self.informationURI,
            semanticVersion: toolVersion,
            rules: [rule]
        )

        let results: [Result] = assessment.files.map { file in
            let verdict = file.verdict(thresholds: assessment.thresholds)
            let level = Level.from(verdict: verdict)
            let added = addedLinesByPath[file.path] ?? []
            let region: Region? = added.min().map { Region(startLine: $0) }
            let location = Location(
                physicalLocation: PhysicalLocation(
                    artifactLocation: ArtifactLocation(uri: file.path),
                    region: region
                )
            )
            return Result(
                ruleId: Self.ruleID,
                level: level,
                message: Message(text: Self.message(for: file, verdict: verdict)),
                locations: [location],
                properties: Properties(
                    riskScore: file.riskScore,
                    confidence: file.confidence,
                    verdict: verdict.rawValue
                )
            )
        }

        self.init(
            schema: Self.schemaURL,
            version: Self.sarifVersion,
            runs: [Run(tool: Tool(driver: driver), results: results)]
        )
    }

    /// Builds a result message summarizing the verdict, risk score, and the top
    /// contributing signals (highest weighted risk first).
    private static func message(for file: FileAssessment, verdict: Verdict) -> String {
        let score = Int(file.riskScore.rounded())
        let top = file.signals
            .filter { $0.risk > 0 }
            .sorted { ($0.risk * $0.weight) > ($1.risk * $1.weight) }
            .prefix(2)
            .map { $0.detail }
        let header = "augur: \(verdict.rawValue) (risk \(score)/100)"
        guard !top.isEmpty else { return header }
        return "\(header) — \(top.joined(separator: "; "))"
    }
}

// MARK: - JSON

extension SarifReport {
    /// Stable, sorted-key SARIF JSON, mirroring `Assessment.jsonData()`.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Stable, sorted-key SARIF JSON as a `String`.
    public func jsonString() throws -> String {
        String(decoding: try jsonData(), as: UTF8.self)
    }
}
