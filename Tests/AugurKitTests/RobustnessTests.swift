import XCTest
@testable import AugurKit

/// Edge-case and robustness coverage across the parsers and the diff surface:
/// malformed / empty inputs must degrade gracefully (no crash, sensible empty
/// result) rather than throwing or producing garbage.
final class RobustnessTests: XCTestCase {

    // MARK: - Coverage: empty & malformed

    func testEmptyLCOVYieldsEmptyReport() {
        let report = CoverageParser.parseLCOV("")
        XCTAssertTrue(report.files.isEmpty)
        XCTAssertEqual(report.query(path: "a.swift", changedLines: [1]).fileMatched, false)
    }

    func testMalformedLCOVIgnoresJunkLines() {
        let lcov = """
        garbage line with no meaning
        SF:a.swift
        DA:not-a-number,also-bad
        DA:5,1
        DA:
        end_of_record
        """
        let report = CoverageParser.parseLCOV(lcov)
        let file = report.files["a.swift"]
        XCTAssertNotNil(file)
        // Only the well-formed DA record survives.
        XCTAssertEqual(file?.instrumented, [5])
        XCTAssertEqual(file?.covered, [5])
    }

    func testMalformedCoberturaXMLDoesNotCrash() {
        // Unterminated tag — parser should not crash; an empty report is acceptable.
        let xml = "<coverage><packages><package><classes><class filename=\"a.swift\"><lines><line number"
        let report = (try? CoverageParser.parse(contents: xml, path: "coverage.xml")) ?? CoverageReport(files: [])
        XCTAssertTrue(report.files.isEmpty || report.files["a.swift"] != nil)
    }

    func testEmptyXMLYieldsEmptyOrThrowsGracefully() {
        // An XML-shaped but contentless document should parse to an empty report
        // or throw a typed ParseError — never crash.
        let xml = "<coverage></coverage>"
        if let report = try? CoverageParser.parse(contents: xml, path: "coverage.xml") {
            XCTAssertTrue(report.files.isEmpty)
        }
    }

    func testEmptyJaCoCoYieldsEmptyReport() throws {
        let xml = "<report name=\"x\"></report>"
        let report = try CoverageParser.parseJaCoCo(xml)
        XCTAssertTrue(report.files.isEmpty)
    }

    func testEmptyGoProfileYieldsEmptyReport() {
        let report = CoverageParser.parseGoProfile("mode: set\n")
        XCTAssertTrue(report.files.isEmpty)
    }

    func testMalformedGoProfileIgnoresBadBlocks() {
        let profile = """
        mode: set
        garbage-without-colon
        example.com/p/a.go:10.2,12.4 2 1
        example.com/p/a.go:bad.block,here 1 1
        """
        let report = CoverageParser.parseGoProfile(profile)
        let file = report.files["example.com/p/a.go"]
        XCTAssertNotNil(file)
        XCTAssertEqual(file?.instrumented, [10, 11, 12])
        XCTAssertEqual(file?.covered, [10, 11, 12])
    }

    func testUndetectableFormatThrows() {
        XCTAssertThrowsError(try CoverageParser.parse(contents: "this is plain prose", path: "notes.txt")) { error in
            guard case CoverageParser.ParseError.undetectableFormat = error else {
                return XCTFail("expected undetectableFormat, got \(error)")
            }
        }
    }

    func testQueryAgainstEmptyChangedLines() {
        let report = CoverageParser.parseLCOV("SF:a.swift\nDA:1,1\nend_of_record")
        let result = report.query(path: "a.swift", changedLines: [])
        XCTAssertTrue(result.fileMatched)
        XCTAssertEqual(result.instrumented, 0)
        XCTAssertNil(result.coveredFraction)
    }

    // MARK: - Diff parsing: numstat

    func testEmptyNumstatYieldsNoFiles() {
        XCTAssertTrue(GitRepository.parseNumstat("").isEmpty)
        XCTAssertTrue(GitRepository.parseNumstat("\n\n").isEmpty)
    }

    func testNumstatBinaryFile() {
        let files = GitRepository.parseNumstat("-\t-\tassets/logo.png\n")
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].isBinary)
        XCTAssertEqual(files[0].linesAdded, 0)
    }

    func testNumstatRenameWithBraces() {
        // git numstat renders renames as `{old => new}` in the path field.
        let files = GitRepository.parseNumstat("3\t1\tsrc/{old => new}/file.swift\n")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "src/{old => new}/file.swift")
        XCTAssertEqual(files[0].linesAdded, 3)
    }

    func testNumstatPathWithSpaces() {
        let files = GitRepository.parseNumstat("5\t2\tsrc/my folder/a file.swift\n")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "src/my folder/a file.swift")
    }

    func testNumstatUnicodePath() {
        let files = GitRepository.parseNumstat("1\t0\tsrc/café/naïve.swift\n")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].path, "src/café/naïve.swift")
    }

    func testNumstatHugeLineCounts() {
        let files = GitRepository.parseNumstat("999999\t888888\tsrc/generated.swift\n")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].linesAdded, 999_999)
        XCTAssertEqual(files[0].churnLines, 1_888_887)
    }

    // MARK: - Diff parsing: unified=0 added lines

    func testEmptyUnifiedDiffYieldsNoAddedLines() {
        XCTAssertTrue(GitRepository.parseUnifiedZeroAddedLines("").isEmpty)
    }

    func testUnifiedDiffSingleAddedLineDefaultCount() {
        let diff = """
        +++ b/src/a.swift
        @@ -0,0 +5 @@
        """
        let added = GitRepository.parseUnifiedZeroAddedLines(diff)
        XCTAssertEqual(added["src/a.swift"], [5])
    }

    func testUnifiedDiffMultiLineHunk() {
        let diff = """
        +++ b/src/a.swift
        @@ -1,0 +10,3 @@
        """
        let added = GitRepository.parseUnifiedZeroAddedLines(diff)
        XCTAssertEqual(added["src/a.swift"], [10, 11, 12])
    }

    func testUnifiedDiffZeroCountHunkContributesNothing() {
        let diff = """
        +++ b/src/a.swift
        @@ -3,2 +3,0 @@
        """
        let added = GitRepository.parseUnifiedZeroAddedLines(diff)
        XCTAssertNil(added["src/a.swift"])
    }

    func testUnifiedDiffDevNullPathIgnored() {
        // A deletion targets /dev/null on the new side; nothing should be recorded.
        let diff = """
        +++ /dev/null
        @@ -1,3 +0,0 @@
        """
        XCTAssertTrue(GitRepository.parseUnifiedZeroAddedLines(diff).isEmpty)
    }

    func testUnifiedDiffPathWithSpacesAndUnicode() {
        let diff = """
        +++ b/src/my dir/café.swift
        @@ -0,0 +1,2 @@
        """
        let added = GitRepository.parseUnifiedZeroAddedLines(diff)
        XCTAssertEqual(added["src/my dir/café.swift"], [1, 2])
    }

    // MARK: - Log parsing

    func testEmptyLogYieldsNoCommits() {
        XCTAssertTrue(GitRepository.parseLog("").isEmpty)
    }

    func testLogCommitWithNoFiles() {
        let output = "\u{1e}abc\u{1f}me@x.io\u{1f}1700000000\u{1f}Empty commit\n"
        let commits = GitRepository.parseLog(output)
        XCTAssertEqual(commits.count, 1)
        XCTAssertTrue(commits[0].files.isEmpty)
    }

    func testLogMalformedHeaderSkipped() {
        // A record with too few fields is skipped rather than mis-parsed.
        let output = "\u{1e}only-two\u{1f}fields\nsrc/a.swift\n"
        XCTAssertTrue(GitRepository.parseLog(output).isEmpty)
    }
}
