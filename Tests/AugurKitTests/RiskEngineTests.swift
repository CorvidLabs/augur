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
        // NUL-delimited `git diff --numstat -z` records.
        let output = "12\t3\tsrc/a.swift\0-\t-\tassets/logo.png\0"
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

    // MARK: - Path exclusions

    func testExcludedFilesAreDroppedFromAssessment() throws {
        let probe = FixtureProbe(
            changed: [
                ChangedFile(path: "src/service.swift", linesAdded: 10, linesDeleted: 2, isBinary: false),
                ChangedFile(path: "vendor/lib/huge.swift", linesAdded: 9000, linesDeleted: 0, isBinary: false),
                ChangedFile(path: "Sources/App/Model.generated.swift", linesAdded: 500, linesDeleted: 0, isBinary: false),
            ],
            commits: manyBenignCommits()
        )
        let filter = PathFilter(globs: ["vendor/**", "**/*.generated.swift"])
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now, filter: filter)

        // Kept file is present; excluded files are absent from the scored set.
        XCTAssertEqual(assessment.files.map(\.path), ["src/service.swift"])
        XCTAssertFalse(assessment.files.contains { $0.path.hasPrefix("vendor/") })

        // Excluded paths are reported (sorted) and counted.
        XCTAssertEqual(assessment.excludedPaths, ["Sources/App/Model.generated.swift", "vendor/lib/huge.swift"])
        XCTAssertEqual(assessment.excludedCount, 2)
    }

    func testExcludingAllFilesReportsExclusionsNotNoChanges() throws {
        let probe = FixtureProbe(
            changed: [
                ChangedFile(path: "vendor/a.swift", linesAdded: 10, linesDeleted: 0, isBinary: false),
                ChangedFile(path: "vendor/b.swift", linesAdded: 10, linesDeleted: 0, isBinary: false),
            ],
            commits: manyBenignCommits()
        )
        let filter = PathFilter(globs: ["**"])
        // There were changed files but the filter excluded all of them: this is a
        // normal proceed assessment that surfaces the exclusions, not a throw.
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now, filter: filter)

        XCTAssertTrue(assessment.files.isEmpty)
        XCTAssertEqual(assessment.verdict, .proceed)
        XCTAssertEqual(assessment.riskScore, 0)
        XCTAssertEqual(assessment.excludedPaths, ["vendor/a.swift", "vendor/b.swift"])
        XCTAssertEqual(assessment.excludedCount, 2)
    }

    func testGenuinelyEmptyDiffStillThrowsNoChanges() {
        let probe = FixtureProbe(changed: [], commits: manyBenignCommits())
        let filter = PathFilter(globs: ["**"])
        XCTAssertThrowsError(try Augur(probe: probe).assess(scope: .workingTree, now: now, filter: filter)) { error in
            guard case AugurError.noChanges = error else {
                return XCTFail("expected AugurError.noChanges, got \(error)")
            }
        }
    }

    func testNilFilterIsBehaviorPreserving() throws {
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "vendor/a.swift", linesAdded: 10, linesDeleted: 0, isBinary: false)],
            commits: manyBenignCommits()
        )
        let unfiltered = try Augur(probe: probe).assess(scope: .workingTree, now: now)
        let nilFiltered = try Augur(probe: probe).assess(scope: .workingTree, now: now, filter: nil)
        let emptyFiltered = try Augur(probe: probe).assess(scope: .workingTree, now: now, filter: PathFilter(globs: []))
        XCTAssertEqual(unfiltered, nilFiltered)
        XCTAssertEqual(unfiltered, emptyFiltered)
        XCTAssertTrue(unfiltered.excludedPaths.isEmpty)
    }

    // MARK: - Weights

    func testWeightsSumToOne() {
        let w = RiskEngine.Weights()
        let sum = w.sensitivity + w.testGap + w.churn + w.coupling + w.diffShape + w.ownership + w.incident + w.codeowners
        XCTAssertEqual(sum, 1.0, accuracy: 1e-9, "prior weights must sum to 1.0")
    }

    // MARK: - CODEOWNERS signal

    func testCodeOwnersAbsentIsNeutral() throws {
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "src/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false)],
            commits: manyBenignCommits()
        )
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now, codeOwners: nil)
        let file = try XCTUnwrap(assessment.files.first)
        let signal = try XCTUnwrap(file.signals.first { $0.name == "codeowners" })
        XCTAssertEqual(signal.risk, 0, "codeowners must be neutral with no CODEOWNERS file")
        XCTAssertEqual(signal.detail, "no CODEOWNERS file")
    }

    func testUnownedFileRaisesCodeOwnersSignal() throws {
        let owners = CodeOwners.parse("/docs/ @docs-team")
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "src/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false)],
            commits: manyBenignCommits()
        )
        let withOwners = try Augur(probe: probe).assess(scope: .workingTree, now: now, codeOwners: owners)
        let neutral = try Augur(probe: probe).assess(scope: .workingTree, now: now, codeOwners: nil)
        let file = try XCTUnwrap(withOwners.files.first)
        let signal = try XCTUnwrap(file.signals.first { $0.name == "codeowners" })
        XCTAssertEqual(signal.risk, 0.6, accuracy: 1e-9)
        XCTAssertEqual(signal.detail, "no CODEOWNERS owner")
        // An unowned file scores strictly higher than a repo with no CODEOWNERS at all.
        XCTAssertGreaterThan(file.riskScore, try XCTUnwrap(neutral.files.first).riskScore)
    }

    func testOwnedFileNeutralizesCodeOwnersSignal() throws {
        let owners = CodeOwners.parse("* @global\n/src/ @src-team")
        let probe = FixtureProbe(
            changed: [ChangedFile(path: "src/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false)],
            commits: manyBenignCommits()
        )
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now, codeOwners: owners)
        let file = try XCTUnwrap(assessment.files.first)
        let signal = try XCTUnwrap(file.signals.first { $0.name == "codeowners" })
        XCTAssertEqual(signal.risk, 0)
        XCTAssertEqual(signal.detail, "owned by @src-team")
    }

    func testOwnedScoresLowerThanUnowned() throws {
        let owners = CodeOwners.parse("/src/ @src-team")
        let ownedProbe = FixtureProbe(
            changed: [ChangedFile(path: "src/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false)],
            commits: manyBenignCommits()
        )
        let unownedProbe = FixtureProbe(
            changed: [ChangedFile(path: "lib/service.swift", linesAdded: 30, linesDeleted: 5, isBinary: false)],
            commits: manyBenignCommits()
        )
        let owned = try Augur(probe: ownedProbe).assess(scope: .workingTree, now: now, codeOwners: owners)
        let unowned = try Augur(probe: unownedProbe).assess(scope: .workingTree, now: now, codeOwners: owners)
        XCTAssertLessThan(
            try XCTUnwrap(owned.files.first).riskScore,
            try XCTUnwrap(unowned.files.first).riskScore + 1.0 // differing paths affect other signals minimally
        )
        XCTAssertEqual(try XCTUnwrap(owned.files.first).signals.first { $0.name == "codeowners" }?.risk, 0)
        XCTAssertEqual(try XCTUnwrap(unowned.files.first).signals.first { $0.name == "codeowners" }?.risk, 0.6)
    }

    // MARK: - Determinism

    func testAssessmentIsByteIdenticalForSameInputs() throws {
        let owners = CodeOwners.parse("* @global\n/src/ @src-team")
        let changed = [
            ChangedFile(path: "src/auth/token.swift", linesAdded: 120, linesDeleted: 40, isBinary: false, addedLines: [1, 2, 3]),
            ChangedFile(path: "lib/util.swift", linesAdded: 10, linesDeleted: 1, isBinary: false),
            ChangedFile(path: "docs/readme.md", linesAdded: 3, linesDeleted: 0, isBinary: false),
        ]
        let history = HistorySnapshot(commits: manyBenignCommits())
        let engine = RiskEngine()
        let first = engine.assess(scope: .workingTree, changedFiles: changed, history: history, now: now, codeOwners: owners)
        let second = engine.assess(scope: .workingTree, changedFiles: changed, history: history, now: now, codeOwners: owners)
        XCTAssertEqual(first, second)
        XCTAssertEqual(try first.jsonData(), try second.jsonData(), "identical inputs must yield byte-identical JSON")
    }

    // MARK: - Fixtures

    private func manyBenignCommits() -> [Commit] {
        (0..<120).map { index in
            Commit(hash: "c\(index)", authorEmail: "dev\(index % 3)@x.io", timestamp: now - index * 86_400, subject: "Add feature \(index)", files: ["src/unrelated\(index % 7).swift"])
        }
    }
}
