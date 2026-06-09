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

    // MARK: - JaCoCo parsing

    func testJaCoCoParsing() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <report name="app">
          <package name="com/foo">
            <sourcefile name="Bar.kt">
              <line nr="10" mi="0" ci="4"/>
              <line nr="11" mi="3" ci="0"/>
              <line nr="12" mi="0" ci="2"/>
            </sourcefile>
            <sourcefile name="Empty.kt">
              <line nr="1" mi="2" ci="0"/>
            </sourcefile>
          </package>
        </report>
        """
        let report = try CoverageParser.parse(contents: xml, path: "jacoco.xml")
        // Path is assembled from package@name + "/" + sourcefile@name.
        let bar = try XCTUnwrap(report.files["com/foo/Bar.kt"])
        XCTAssertEqual(bar.instrumented, [10, 11, 12])
        // Covered when ci > 0 (10 and 12); 11 has ci=0 so it is uncovered.
        XCTAssertEqual(bar.covered, [10, 12])
        let empty = try XCTUnwrap(report.files["com/foo/Empty.kt"])
        XCTAssertEqual(empty.instrumented, [1])
        XCTAssertTrue(empty.covered.isEmpty)
    }

    func testJaCoCoEmptyPackagePath() throws {
        // A package with an empty name yields the bare sourcefile name.
        let xml = """
        <report>
          <package name="">
            <sourcefile name="Top.kt">
              <line nr="1" mi="0" ci="1"/>
            </sourcefile>
          </package>
        </report>
        """
        let report = try CoverageParser.parseJaCoCo(xml)
        let top = try XCTUnwrap(report.files["Top.kt"])
        XCTAssertEqual(top.instrumented, [1])
        XCTAssertEqual(top.covered, [1])
    }

    // MARK: - Go coverprofile parsing

    func testGoProfileParsing() throws {
        // Two blocks for the same file: lines 5...7 covered (count 3), 9...10 not.
        let profile = """
        mode: set
        github.com/acme/app/calc.go:5.2,7.16 2 3
        github.com/acme/app/calc.go:9.2,10.10 1 0
        github.com/acme/app/other.go:1.1,1.20 1 1
        """
        let report = try CoverageParser.parse(contents: profile, path: "cover.out")
        let calc = try XCTUnwrap(report.files["github.com/acme/app/calc.go"])
        XCTAssertEqual(calc.instrumented, [5, 6, 7, 9, 10])
        XCTAssertEqual(calc.covered, [5, 6, 7])
        let other = try XCTUnwrap(report.files["github.com/acme/app/other.go"])
        XCTAssertEqual(other.instrumented, [1])
        XCTAssertEqual(other.covered, [1])
    }

    func testGoProfileLineCoveredByAnyBlock() throws {
        // Overlapping blocks: line 6 is in an uncovered block AND a covered one;
        // covered wins because ANY covering block with count>0 marks it covered.
        let profile = """
        mode: count
        a/x.go:6.1,6.10 1 0
        a/x.go:6.1,8.10 1 4
        """
        let report = CoverageParser.parseGoProfile(profile)
        let file = try XCTUnwrap(report.files["a/x.go"])
        XCTAssertEqual(file.instrumented, [6, 7, 8])
        XCTAssertEqual(file.covered, [6, 7, 8])
    }

    func testGoBlockParsing() {
        let block = CoverageParser.parseGoBlock("path/to/file.go:12.4,15.2 3 7")
        XCTAssertEqual(block?.path, "path/to/file.go")
        XCTAssertEqual(block?.startLine, 12)
        XCTAssertEqual(block?.endLine, 15)
        XCTAssertEqual(block?.count, 7)
        // Malformed lines are rejected.
        XCTAssertNil(CoverageParser.parseGoBlock("garbage without colon"))
    }

    func testFormatDetection() {
        XCTAssertEqual(CoverageParser.detectFormat(path: "x.info", contents: ""), .lcov)
        XCTAssertEqual(CoverageParser.detectFormat(path: "x.xml", contents: ""), .cobertura)
        XCTAssertEqual(CoverageParser.detectFormat(path: "", contents: "<?xml version=\"1.0\"?><coverage/>"), .cobertura)
        XCTAssertEqual(CoverageParser.detectFormat(path: "", contents: "SF:a.swift\nDA:1,1\n"), .lcov)
        XCTAssertNil(CoverageParser.detectFormat(path: "x.txt", contents: "hello"))
        // JaCoCo: <report> + <sourcefile> markers, even with an .xml extension.
        let jacoco = "<?xml version=\"1.0\"?><report><package name=\"p\"><sourcefile name=\"A.kt\"/></package></report>"
        XCTAssertEqual(CoverageParser.detectFormat(path: "jacoco.xml", contents: jacoco), .jacoco)
        XCTAssertEqual(CoverageParser.detectFormat(path: "", contents: jacoco), .jacoco)
        // Go coverprofile: first non-empty line begins "mode:".
        XCTAssertEqual(CoverageParser.detectFormat(path: "cover.out", contents: "mode: set\na/b.go:1.1,2.2 1 1\n"), .go)
        XCTAssertEqual(CoverageParser.detectFormat(path: "", contents: "mode: atomic\na.go:1.1,1.2 1 0\n"), .go)
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

    func testJaCoCoCoveredChangedLinesLowerTestGapRisk() throws {
        // The diff path is repo-relative (com/foo/Bar.kt); JaCoCo assembles the
        // same path from package + sourcefile, so suffix matching reconciles them.
        let changed = [ChangedFile(path: "com/foo/Bar.kt", linesAdded: 3, linesDeleted: 0, isBinary: false, addedLines: [10, 11, 12])]
        let probe = CoverageFixtureProbe(changed: changed, commits: manyBenignCommits())

        let coveredXML = """
        <report><package name="com/foo"><sourcefile name="Bar.kt">
          <line nr="10" mi="0" ci="4"/>
          <line nr="11" mi="0" ci="2"/>
          <line nr="12" mi="0" ci="1"/>
        </sourcefile></package></report>
        """
        let uncoveredXML = """
        <report><package name="com/foo"><sourcefile name="Bar.kt">
          <line nr="10" mi="4" ci="0"/>
          <line nr="11" mi="2" ci="0"/>
          <line nr="12" mi="1" ci="0"/>
        </sourcefile></package></report>
        """
        let coveredReport = try CoverageParser.parseJaCoCo(coveredXML)
        let uncoveredReport = try CoverageParser.parseJaCoCo(uncoveredXML)

        let covered = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: coveredReport)
        let uncovered = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: uncoveredReport)

        let coveredGap = try XCTUnwrap(covered.files.first?.signals.first { $0.name == "test-gap" })
        let uncoveredGap = try XCTUnwrap(uncovered.files.first?.signals.first { $0.name == "test-gap" })
        XCTAssertEqual(coveredGap.risk, 0, accuracy: 0.0001)
        XCTAssertEqual(uncoveredGap.risk, 1, accuracy: 0.0001)
        XCTAssertLessThan(try XCTUnwrap(covered.files.first).riskScore, try XCTUnwrap(uncovered.files.first).riskScore)
        XCTAssertTrue(coveredGap.detail.contains("3/3"))
    }

    func testGoProfileCoveredChangedLinesLowerTestGapRisk() throws {
        let changed = [ChangedFile(path: "calc.go", linesAdded: 3, linesDeleted: 0, isBinary: false, addedLines: [5, 6, 7])]
        let probe = CoverageFixtureProbe(changed: changed, commits: manyBenignCommits())

        let coveredProfile = """
        mode: set
        github.com/acme/app/calc.go:5.2,7.16 3 4
        """
        let uncoveredProfile = """
        mode: set
        github.com/acme/app/calc.go:5.2,7.16 3 0
        """
        let coveredReport = CoverageParser.parseGoProfile(coveredProfile)
        let uncoveredReport = CoverageParser.parseGoProfile(uncoveredProfile)

        let covered = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: coveredReport)
        let uncovered = try Augur(probe: probe).assess(scope: .workingTree, now: now, coverage: uncoveredReport)

        let coveredGap = try XCTUnwrap(covered.files.first?.signals.first { $0.name == "test-gap" })
        let uncoveredGap = try XCTUnwrap(uncovered.files.first?.signals.first { $0.name == "test-gap" })
        XCTAssertEqual(coveredGap.risk, 0, accuracy: 0.0001)
        XCTAssertEqual(uncoveredGap.risk, 1, accuracy: 0.0001)
        XCTAssertLessThan(try XCTUnwrap(covered.files.first).riskScore, try XCTUnwrap(uncovered.files.first).riskScore)
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
