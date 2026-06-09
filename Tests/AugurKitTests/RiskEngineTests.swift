import XCTest
@testable import AugurKit

/// In-memory probe so the engine can be tested without git.
private struct FixtureProbe: RepositoryProbe {
    let changed: [ChangedFile]
    let commits: [Commit]

    var head: String = ""

    func changedFiles(in scope: DiffScope) throws -> [ChangedFile] { changed }
    func recentCommits(limit: Int) throws -> [Commit] { commits }
    func headSHA() throws -> String { head }
}

final class RiskEngineTests: XCTestCase {
    private let now = 1_700_000_000

    func testTrivialDocChangeProceeds() throws {
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "docs/readme.md", linesAdded: 3, linesDeleted: 1, isBinary: false)],
            commits: manyBenignCommits()
        )
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now)
        XCTAssertEqual(assessment.verdict, .proceed)
        XCTAssertLessThan(assessment.riskScore, 35)
    }

    func testAuthChangeWithoutTestsEscalates() throws {
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "src/auth/token.swift", linesAdded: 120, linesDeleted: 40, isBinary: false)],
            commits: manyBenignCommits()
        )
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now)
        XCTAssertGreaterThanOrEqual(assessment.verdict, .review)
        let file = try XCTUnwrap(assessment.files.first)
        XCTAssertTrue(file.signals.contains { $0.name == "sensitivity" && $0.risk > 0 })
        XCTAssertTrue(file.signals.contains { $0.name == "test-gap" && $0.risk > 0 })
    }

    func testTestAlongsideLowersRisk() throws {
        let withTests = FixtureProbe(
            changed: [
                ChangedFile(path: "src/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false),
                ChangedFile(path: "Tests/ServiceTests.swift", linesAdded: 40, linesDeleted: 0, isBinary: false),
            ],
            commits: manyBenignCommits()
        )
        let withoutTests = FixtureProbe(
            changed: [ChangedFile(path: "src/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false)],
            commits: manyBenignCommits()
        )
        let a = try Augur(probe: withTests).assess(scope: .workingTree, now: now)
        let b = try Augur(probe: withoutTests).assess(scope: .workingTree, now: now)
        let aFile = try XCTUnwrap(a.files.first { $0.path == "src/service.swift" })
        let bFile = try XCTUnwrap(b.files.first { $0.path == "src/service.swift" })
        XCTAssertLessThan(aFile.riskScore, bFile.riskScore)
    }

    func testCalibrationConfidenceGrowsWithHistory() {
        let low = RiskEngine.calibrationConfidence(totalCommits: 10, incidentCommits: 0)
        let high = RiskEngine.calibrationConfidence(totalCommits: 400, incidentCommits: 40)
        XCTAssertLessThan(low, 0.25)
        XCTAssertGreaterThan(high, 0.6)
    }

    func testIncidentHistoryRaisesRiskOnlyWhenCalibrated() throws {
        // A file repeatedly implicated in reverts, with rich history.
        var commits: [Commit] = []
        for index in 0..<200 {
            let subject = index % 4 == 0 ? "Revert \"bad change\"" : "Add feature \(index)"
            commits.append(Commit(hash: "h\(index)", authorEmail: "a@x.io", timestamp: now - index * 3600, subject: subject, files: ["src/fragile.swift"]))
        }
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "src/fragile.swift", linesAdded: 10, linesDeleted: 2, isBinary: false)],
            commits: commits
        )
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now)
        let file = try XCTUnwrap(assessment.files.first)
        XCTAssertTrue(file.signals.contains { $0.name == "incident" && $0.risk > 0 })
        XCTAssertGreaterThan(assessment.calibration.confidence, 0.5)
    }

    func testNumstatParsing() {
        let output = "12\t3\tsrc/a.swift\n-\t-\tassets/logo.png\n"
        let files = GitRepository.parseNumstat(output)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].linesAdded, 12)
        XCTAssertTrue(files[1].isBinary)
    }

    func testLogParsing() {
        let output = "\u{1e}abc\u{1f}me@x.io\u{1f}1700000000\u{1f}Fix: thing\nsrc/a.swift\nsrc/b.swift\n"
        let commits = GitRepository.parseLog(output)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits[0].files, ["src/a.swift", "src/b.swift"])
        XCTAssertTrue(HistorySnapshot.looksLikeIncident(commits[0].subject))
    }

    // MARK: - Thresholds

    func testDefaultThresholdsMatchOriginalBehavior() {
        XCTAssertEqual(Thresholds.default.review, 35)
        XCTAssertEqual(Thresholds.default.block, 65)
        // Verdict.from with explicit defaults equals the no-argument convenience.
        for score in stride(from: 0.0, through: 100.0, by: 0.5) {
            XCTAssertEqual(
                Verdict.from(riskScore: score),
                Verdict.from(riskScore: score, thresholds: .default)
            )
        }
        // Boundary checks mirror the original < 35 / < 65 mapping.
        XCTAssertEqual(Verdict.from(riskScore: 34.9), .proceed)
        XCTAssertEqual(Verdict.from(riskScore: 35), .review)
        XCTAssertEqual(Verdict.from(riskScore: 64.9), .review)
        XCTAssertEqual(Verdict.from(riskScore: 65), .block)
    }

    func testCustomThresholdsChangeVerdict() throws {
        // A moderate change that proceeds under defaults can be forced to review/block
        // by tightening the thresholds — same scoring, different cutoffs.
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "src/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false)],
            commits: manyBenignCommits()
        )
        let lenient = try Augur(probe: probe, engine: RiskEngine(thresholds: .default))
            .assess(scope: .workingTree, now: now)
        let strict = try Augur(probe: probe, engine: RiskEngine(thresholds: Thresholds(review: 1, block: 2)))
            .assess(scope: .workingTree, now: now)
        XCTAssertEqual(lenient.riskScore, strict.riskScore, accuracy: 0.0001, "thresholds must not change the score")
        XCTAssertGreaterThan(strict.verdict, lenient.verdict)
        XCTAssertEqual(strict.verdict, .block)
        XCTAssertEqual(strict.thresholds, Thresholds(review: 1, block: 2))
    }

    func testThresholdsClampReviewBelowBlock() {
        let thresholds = Thresholds(review: 90, block: 50)
        XCTAssertEqual(thresholds.block, 50)
        XCTAssertEqual(thresholds.review, 50)
    }

    // MARK: - Custom rules

    func testCustomRulesMergeWithDefaults() throws {
        let custom = SensitivityRule(label: "internal-api", risk: 0.7, fragments: ["internal/"])
        let merged = SensitivityRuleset.default + [custom]
        // The custom path now matches; a default category still matches too.
        XCTAssertEqual(SensitivityRuleset.match("pkg/internal/api.swift", rules: merged)?.label, "internal-api")
        XCTAssertEqual(SensitivityRuleset.match("src/auth/token.swift", rules: merged)?.label, "auth")
        // Without the custom rule, the internal path is not sensitive.
        XCTAssertNil(SensitivityRuleset.match("pkg/internal/api.swift", rules: SensitivityRuleset.default))
    }

    func testCustomRuleRaisesRiskInEngine() throws {
        let custom = [SensitivityRule(label: "internal-api", risk: 0.9, fragments: ["internal/"])]
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "pkg/internal/api.swift", linesAdded: 50, linesDeleted: 10, isBinary: false)],
            commits: manyBenignCommits()
        )
        let withRule = try Augur(probe: probe, engine: RiskEngine(rules: SensitivityRuleset.default + custom))
            .assess(scope: .workingTree, now: now)
        let withoutRule = try Augur(probe: probe, engine: RiskEngine())
            .assess(scope: .workingTree, now: now)
        let withFile = try XCTUnwrap(withRule.files.first)
        XCTAssertTrue(withFile.signals.contains { $0.name == "sensitivity" && $0.risk > 0 })
        XCTAssertGreaterThan(withRule.riskScore, withoutRule.riskScore)
    }

    // MARK: - Calibration cache

    func testCalibrationCacheRoundTrips() throws {
        var commits: [Commit] = []
        for index in 0..<150 {
            let subject = index % 5 == 0 ? "Revert \"oops\"" : "Add feature \(index)"
            commits.append(
                Commit(
                    hash: "h\(index)",
                    authorEmail: "dev\(index % 4)@x.io",
                    timestamp: now - index * 3600,
                    subject: subject,
                    files: ["src/fragile.swift", "src/partner\(index % 3).swift"]
                )
            )
        }
        let changed = [ChangedFile(path: "src/fragile.swift", linesAdded: 12, linesDeleted: 3, isBinary: false)]

        // Live snapshot.
        let live = HistorySnapshot(commits: commits)
        let liveAssessment = RiskEngine().assess(scope: .workingTree, changedFiles: changed, history: live, now: now)

        // Encode -> decode -> rebuild.
        let cache = live.makeCache(head: "deadbeef")
        let decoded = try CalibrationCache.decoded(from: try cache.jsonData())
        XCTAssertEqual(decoded, cache)
        XCTAssertEqual(decoded.head, "deadbeef")

        let rebuilt = HistorySnapshot(cache: decoded)
        let rebuiltAssessment = RiskEngine().assess(scope: .workingTree, changedFiles: changed, history: rebuilt, now: now)

        // Scoring is identical across the cache boundary.
        XCTAssertEqual(rebuiltAssessment, liveAssessment)
        XCTAssertEqual(rebuilt.churnCount("src/fragile.swift"), live.churnCount("src/fragile.swift"))
        XCTAssertEqual(rebuilt.authorCount("src/fragile.swift"), live.authorCount("src/fragile.swift"))
        XCTAssertEqual(rebuilt.isIncidentProne("src/fragile.swift"), live.isIncidentProne("src/fragile.swift"))
        XCTAssertEqual(
            rebuilt.topPartner("src/fragile.swift")?.partner,
            live.topPartner("src/fragile.swift")?.partner
        )
    }

    func testCacheReportsBandAndConfidence() {
        let commits = (0..<400).map { index in
            Commit(hash: "h\(index)", authorEmail: "a@x.io", timestamp: now - index * 3600,
                   subject: index % 10 == 0 ? "hotfix: x" : "Add \(index)", files: ["src/a.swift"])
        }
        let cache = HistorySnapshot(commits: commits).makeCache(head: "abc")
        XCTAssertEqual(cache.totalCommits, 400)
        XCTAssertGreaterThan(cache.confidence, 0.6)
        XCTAssertEqual(cache.band, "history-backed")
    }

    // MARK: - Fixtures

    private func manyBenignCommits() -> [Commit] {
        (0..<120).map { index in
            Commit(hash: "c\(index)", authorEmail: "dev\(index % 3)@x.io", timestamp: now - index * 86_400, subject: "Add feature \(index)", files: ["src/unrelated\(index % 7).swift"])
        }
    }
}
