import XCTest
@testable import AugurKit

/// In-memory probe so the engine can be tested without git.
private struct FixtureProbe: RepositoryProbe {
    let changed: [ChangedFile]
    let commits: [Commit]

    func changedFiles(in scope: DiffScope) throws -> [ChangedFile] { changed }
    func recentCommits(limit: Int) throws -> [Commit] { commits }
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

    // MARK: - Fixtures

    private func manyBenignCommits() -> [Commit] {
        (0..<120).map { index in
            Commit(hash: "c\(index)", authorEmail: "dev\(index % 3)@x.io", timestamp: now - index * 86_400, subject: "Add feature \(index)", files: ["src/unrelated\(index % 7).swift"])
        }
    }
}
