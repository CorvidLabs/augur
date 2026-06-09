import XCTest
@testable import AugurKit

/// In-memory probe whose changed files carry added-line ranges, for testing the
/// coverage-aware test-gap signal without git.
private struct CoverageFixtureProbe: RepositoryProbe {
    let changed: [ChangedFile]
    let commits: [Commit]

    func changedFiles(in scope: DiffScope) throws -> [ChangedFile] { changed }
    func recentCommits(limit: Int) throws -> [Commit] { commits }
}

final class CoverageTests: XCTestCase {
    private let now = 1_700_000_000

    // MARK: - LCOV parsing

    func testLCOVParsing() throws {
        let lcov = """
        TN:
        SF:Sources/App/Service.swift
        DA:10,5
        DA:11,0
        DA:12,3
        end_of_record
        SF:Sources/App/Other.swift
        DA:1,0
        end_of_record
        """
        let report = try CoverageParser.parse(contents: lcov, path: "lcov.info")
        let service = try XCTUnwrap(report.files["Sources/App/Service.swift"])
        XCTAssertEqual(service.instrumented, [10, 11, 12])
        XCTAssertEqual(service.covered, [10, 12])
        let other = try XCTUnwrap(report.files["Sources/App/Other.swift"])
        XCTAssertEqual(other.instrumented, [1])
        XCTAssertTrue(other.covered.isEmpty)
    }

    func testLCOVMergesDuplicateRecords() throws {
        let lcov = """
        SF:a.swift
        DA:1,1
        end_of_record
        SF:a.swift
        DA:2,0
        end_of_record
        """
        let report = CoverageParser.parseLCOV(lcov)
        let file = try XCTUnwrap(report.files["a.swift"])
        XCTAssertEqual(file.instrumented, [1, 2])
        XCTAssertEqual(file.covered, [1])
    }

    // MARK: - Cobertura parsing

    func testCoberturaParsing() throws {
        let xml = """
        <?xml version="1.0"?>
        <coverage>
          <packages>
            <package name="app">
              <classes>
                <class filename="src/Service.swift">
                  <lines>
                    <line number="10" hits="5"/>
                    <line number="11" hits="0"/>
                    <line number="12" hits="2"/>
                  </lines>
                </class>
                <class filename="src/Empty.swift">
                  <lines>
                    <line number="1" hits="0"/>
                  </lines>
                </class>
              </classes>
            </package>
          </packages>
        </coverage>
        """
        let report = try CoverageParser.parse(contents: xml, path: "coverage.xml")
        let service = try XCTUnwrap(report.files["src/Service.swift"])
        XCTAssertEqual(service.instrumented, [10, 11, 12])
        XCTAssertEqual(service.covered, [10, 12])
        XCTAssertEqual(report.files["src/Empty.swift"]?.covered, [])
    }

    func testFormatDetection() {
        XCTAssertEqual(CoverageParser.detectFormat(path: "x.info", contents: ""), .lcov)
        XCTAssertEqual(CoverageParser.detectFormat(path: "x.xml", contents: ""), .cobertura)
        XCTAssertEqual(CoverageParser.detectFormat(path: "", contents: "<?xml version=\"1.0\"?><coverage/>"), .cobertura)
        XCTAssertEqual(CoverageParser.detectFormat(path: "", contents: "SF:a.swift\nDA:1,1\n"), .lcov)
        XCTAssertNil(CoverageParser.detectFormat(path: "x.txt", contents: "hello"))
    }

    // MARK: - Suffix path matching

    func testSuffixPathMatching() {
        let report = CoverageReport(files: [
            CoverageReport.FileCoverage(path: "/build/checkout/Sources/App/Service.swift", instrumented: [1, 2], covered: [1]),
        ])
        // Diff path lacks the build/checkout prefix; suffix still matches.
        let matched = report.matchFile(diffPath: "Sources/App/Service.swift")
        XCTAssertEqual(matched?.path, "/build/checkout/Sources/App/Service.swift")
        // A path sharing no trailing component does not match.
        XCTAssertNil(report.matchFile(diffPath: "Sources/Other/Thing.swift"))
    }

    func testSuffixMatchPrefersLongerOverlap() {
        let report = CoverageReport(files: [
            CoverageReport.FileCoverage(path: "a/util.swift", instrumented: [1], covered: [1]),
            CoverageReport.FileCoverage(path: "deep/pkg/util.swift", instrumented: [2], covered: [2]),
        ])
        // "pkg/util.swift" shares 2 trailing components with the second only.
        XCTAssertEqual(report.matchFile(diffPath: "pkg/util.swift")?.path, "deep/pkg/util.swift")
    }

    func testQueryRestrictsToInstrumentedChangedLines() {
        let report = CoverageReport(files: [
            CoverageReport.FileCoverage(path: "a.swift", instrumented: [10, 11, 12], covered: [10, 12]),
        ])
        // Changed lines 10,11,13: 13 is not instrumented; 10,11 are (10 covered).
        let result = report.query(path: "a.swift", changedLines: [10, 11, 13])
        XCTAssertEqual(result.instrumented, 2)
        XCTAssertEqual(result.covered, 1)
        XCTAssertEqual(result.coveredFraction, 0.5)
        XCTAssertTrue(result.fileMatched)
    }

    func testQueryMissesUnknownFile() {
        let report = CoverageReport(files: [])
        let result = report.query(path: "a.swift", changedLines: [1])
        XCTAssertFalse(result.fileMatched)
        XCTAssertNil(result.coveredFraction)
    }

    // MARK: - Unified=0 diff parsing

    func testUnifiedZeroAddedLineParsing() {
        let diff = """
        diff --git a/src/a.swift b/src/a.swift
        --- a/src/a.swift
        +++ b/src/a.swift
        @@ -0,0 +1,3 @@
        +line one
        +line two
        +line three
        @@ -10 +14 @@
        +single replaced line
        """
        let added = GitRepository.parseUnifiedZeroAddedLines(diff)
        XCTAssertEqual(added["src/a.swift"], [1, 2, 3, 14])
    }

    func testHunkRangeDefaultsCountToOne() {
        // "+14" with no count means a single line at 14.
        XCTAssertEqual(GitRepository.parseHunkAddedRange("@@ -10 +14 @@")?.start, 14)
        XCTAssertEqual(GitRepository.parseHunkAddedRange("@@ -10 +14 @@")?.count, 1)
        // "+14,0" means a pure deletion: zero added lines.
        XCTAssertEqual(GitRepository.parseHunkAddedRange("@@ -10,2 +14,0 @@")?.count, 0)
    }

    // MARK: - Scoring: coverage lowers/raises test-gap

    func testCoveredChangedLinesLowerTestGapRiskVsUncovered() throws {
        let changed = [ChangedFile(path: "src/service.swift", linesAdded: 3, linesDeleted: 0, isBinary: false, addedLines: [10, 11, 12])]
        let probe = CoverageFixtureProbe(changed: changed, commits: manyBenignCommits())

        let coveredReport = CoverageReport(files: [
            CoverageReport.FileCoverage(path: "src/service.swift", instrumented: [10, 11, 12], covered: [10, 11, 12]),
        ])
        let uncoveredReport = CoverageReport(files: [
            CoverageReport.FileCoverage(path: "src/service.swift", instrumented: [10, 11, 12], covered: []),
        ])

        let covered = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: coveredReport)
        let uncovered = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: uncoveredReport)

        let coveredFile = try XCTUnwrap(covered.files.first)
        let uncoveredFile = try XCTUnwrap(uncovered.files.first)
        let coveredGap = try XCTUnwrap(coveredFile.signals.first { $0.name == "test-gap" })
        let uncoveredGap = try XCTUnwrap(uncoveredFile.signals.first { $0.name == "test-gap" })

        XCTAssertEqual(coveredGap.risk, 0, accuracy: 0.0001)
        XCTAssertEqual(uncoveredGap.risk, 1, accuracy: 0.0001)
        XCTAssertLessThan(coveredFile.riskScore, uncoveredFile.riskScore)
        XCTAssertTrue(coveredGap.detail.contains("3/3"))
    }

    func testFileAbsentFromCoverageIsHighRisk() throws {
        let changed = [ChangedFile(path: "src/orphan.swift", linesAdded: 2, linesDeleted: 0, isBinary: false, addedLines: [1, 2])]
        let probe = CoverageFixtureProbe(changed: changed, commits: manyBenignCommits())
        let report = CoverageReport(files: [
            CoverageReport.FileCoverage(path: "src/other.swift", instrumented: [1], covered: [1]),
        ])
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: report)
        let file = try XCTUnwrap(assessment.files.first)
        let gap = try XCTUnwrap(file.signals.first { $0.name == "test-gap" })
        XCTAssertEqual(gap.risk, 0.7, accuracy: 0.0001)
        XCTAssertEqual(gap.detail, "not in coverage report")
    }

    func testNoCoveragePreservesHeuristic() throws {
        // Same input with and without coverage: no coverage keeps the heuristic 0.7.
        let changed = [ChangedFile(path: "src/service.swift", linesAdded: 3, linesDeleted: 0, isBinary: false, addedLines: [10, 11, 12])]
        let probe = CoverageFixtureProbe(changed: changed, commits: manyBenignCommits())
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now)
        let file = try XCTUnwrap(assessment.files.first)
        let gap = try XCTUnwrap(file.signals.first { $0.name == "test-gap" })
        XCTAssertEqual(gap.risk, 0.7, accuracy: 0.0001)
        XCTAssertEqual(gap.detail, "code changed with no test in the changeset")
    }

    func testInstrumentedButUnmeasurableChangeFallsBackToHeuristic() throws {
        // Changed lines are none-instrumented (e.g. comments): no precise ratio,
        // so the heuristic applies.
        let changed = [ChangedFile(path: "src/service.swift", linesAdded: 1, linesDeleted: 0, isBinary: false, addedLines: [99])]
        let probe = CoverageFixtureProbe(changed: changed, commits: manyBenignCommits())
        let report = CoverageReport(files: [
            CoverageReport.FileCoverage(path: "src/service.swift", instrumented: [10, 11], covered: [10]),
        ])
        let assessment = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: report)
        let file = try XCTUnwrap(assessment.files.first)
        let gap = try XCTUnwrap(file.signals.first { $0.name == "test-gap" })
        // File matched, but changed line 99 is not instrumented → heuristic 0.7.
        XCTAssertEqual(gap.risk, 0.7, accuracy: 0.0001)
    }

    // MARK: - Fixtures

    private func manyBenignCommits() -> [Commit] {
        (0..<120).map { index in
            Commit(hash: "c\(index)", authorEmail: "dev\(index % 3)@x.io", timestamp: now - index * 86_400, subject: "Add feature \(index)", files: ["src/unrelated\(index % 7).swift"])
        }
    }
}
