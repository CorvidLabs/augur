import XCTest
@testable import AugurKit

// MARK: - Markdown Reporter Tests

/// Tests for the GitHub-flavored markdown `MarkdownReporter`.
///
/// Every fixture is a fully in-code, deterministic `Assessment` (no `Date()`, no
/// git), so the rendered markdown is stable across runs and machines. These
/// tests lock the verdict heading per verdict, the riskiest-first table order,
/// the presence of the sticky-comment marker, and the row-cap overflow line.
final class MarkdownReporterTests: XCTestCase {
    // MARK: - Fixtures

    private func file(_ path: String, risk: Double, signals: [Signal] = []) -> FileAssessment {
        let signals = signals.isEmpty
            ? [Signal(name: "churn", risk: 0.5, weight: 0.3, detail: "lines changed")]
            : signals
        return FileAssessment(path: path, riskScore: risk, signals: signals)
    }

    private func assessment(verdict: Verdict, risk: Double, files: [FileAssessment]) -> Assessment {
        Assessment(
            scope: "main..HEAD",
            riskScore: risk,
            verdict: verdict,
            calibration: Calibration(confidence: 0.5, totalCommits: 100, incidentCommits: 12),
            files: files
        )
    }

    // MARK: - Heading per verdict

    func testProceedHeadingEmoji() {
        let rendered = MarkdownReporter.render(
            assessment(verdict: .proceed, risk: 12, files: [file("a.swift", risk: 12)])
        )
        XCTAssertTrue(rendered.hasPrefix("### augur: ✅ PROCEED - risk 12/100"))
    }

    func testReviewHeadingEmoji() {
        let rendered = MarkdownReporter.render(
            assessment(verdict: .review, risk: 40, files: [file("a.swift", risk: 40)])
        )
        XCTAssertTrue(rendered.hasPrefix("### augur: ⚠️ REVIEW - risk 40/100"))
    }

    func testBlockHeadingEmoji() {
        let rendered = MarkdownReporter.render(
            assessment(verdict: .block, risk: 80, files: [file("a.swift", risk: 80)])
        )
        XCTAssertTrue(rendered.hasPrefix("### augur: ⛔ BLOCK - risk 80/100"))
    }

    // MARK: - Confidence / calibration line

    func testConfidenceLine() {
        let rendered = MarkdownReporter.render(
            assessment(verdict: .review, risk: 40, files: [file("a.swift", risk: 40)])
        )
        XCTAssertTrue(rendered.contains("Confidence 60/100 - calibration weak (12 incidents / 100 commits)."))
    }

    // MARK: - Table order (riskiest first)

    func testTableRowsAreRiskiestFirst() {
        let rendered = MarkdownReporter.render(
            assessment(
                verdict: .review,
                risk: 50,
                files: [
                    file("low.swift", risk: 10),
                    file("high.swift", risk: 90),
                    file("mid.swift", risk: 50)
                ]
            )
        )
        guard
            let high = rendered.range(of: "high.swift"),
            let mid = rendered.range(of: "mid.swift"),
            let low = rendered.range(of: "low.swift")
        else {
            XCTFail("expected all rows present")
            return
        }
        XCTAssertTrue(high.lowerBound < mid.lowerBound)
        XCTAssertTrue(mid.lowerBound < low.lowerBound)
    }

    func testTableHeaderPresent() {
        let rendered = MarkdownReporter.render(
            assessment(verdict: .review, risk: 40, files: [file("a.swift", risk: 40)])
        )
        XCTAssertTrue(rendered.contains("| File | Risk | Verdict | Top signal |"))
    }

    func testTopSignalIsHighestWeighted() {
        let signals = [
            Signal(name: "churn", risk: 0.5, weight: 0.1, detail: "100 lines changed"),
            Signal(name: "sensitivity", risk: 0.9, weight: 0.4, detail: "matches auth path")
        ]
        let rendered = MarkdownReporter.render(
            assessment(verdict: .review, risk: 40, files: [file("a.swift", risk: 40, signals: signals)])
        )
        XCTAssertTrue(rendered.contains("sensitivity: matches auth path"))
    }

    func testNoContributingSignalRendersDash() {
        let signals = [Signal(name: "churn", risk: 0.0, weight: 0.3, detail: "no churn")]
        let rendered = MarkdownReporter.render(
            assessment(verdict: .proceed, risk: 5, files: [file("a.swift", risk: 5, signals: signals)])
        )
        XCTAssertTrue(rendered.contains("| - |"))
    }

    // MARK: - Marker

    func testMarkerPresentOnOwnLine() {
        let rendered = MarkdownReporter.render(
            assessment(verdict: .review, risk: 40, files: [file("a.swift", risk: 40)])
        )
        XCTAssertTrue(rendered.contains(MarkdownReporter.marker))
        let lines = rendered.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertTrue(lines.contains(MarkdownReporter.marker))
    }

    // MARK: - Row cap

    func testRowCapAddsOverflowLine() {
        let count = MarkdownReporter.maxRows + 7
        let files = (0..<count).map { index in
            file(String(format: "file%03d.swift", index), risk: Double(count - index))
        }
        let rendered = MarkdownReporter.render(assessment(verdict: .review, risk: 50, files: files))
        // Count rendered data rows (pipe-prefixed lines minus the two header lines).
        let pipeRows = rendered.split(separator: "\n").filter { $0.hasPrefix("| ") }.count
        XCTAssertEqual(pipeRows, MarkdownReporter.maxRows + 2)  // + header + separator
        XCTAssertTrue(rendered.contains("and 7 more files."))
    }

    func testNoOverflowLineWhenUnderCap() {
        let files = [file("a.swift", risk: 40), file("b.swift", risk: 20)]
        let rendered = MarkdownReporter.render(assessment(verdict: .review, risk: 40, files: files))
        XCTAssertFalse(rendered.contains("more file"))
    }

    // MARK: - Determinism

    func testDeterministicOutput() {
        let files = [file("b.swift", risk: 30), file("a.swift", risk: 30)]
        let first = MarkdownReporter.render(assessment(verdict: .review, risk: 40, files: files))
        let second = MarkdownReporter.render(assessment(verdict: .review, risk: 40, files: files))
        XCTAssertEqual(first, second)
    }

    func testNoEmDash() {
        let rendered = MarkdownReporter.render(
            assessment(verdict: .review, risk: 40, files: [file("a.swift", risk: 40)])
        )
        XCTAssertFalse(rendered.contains("\u{2014}"))
    }

    // MARK: - Pipe escaping

    func testPipeInDetailIsEscaped() {
        let signals = [Signal(name: "churn", risk: 0.5, weight: 0.3, detail: "a | b")]
        let rendered = MarkdownReporter.render(
            assessment(verdict: .review, risk: 40, files: [file("a.swift", risk: 40, signals: signals)])
        )
        XCTAssertTrue(rendered.contains("a \\| b"))
    }

    // MARK: - Golden snapshot

    func testMultiFileSnapshot() {
        let files = [
            FileAssessment(
                path: "Sources/Auth/TokenStore.swift",
                riskScore: 82,
                signals: [
                    Signal(name: "sensitivity", risk: 1.0, weight: 0.25, detail: "matches auth path"),
                    Signal(name: "test-gap", risk: 0.9, weight: 0.2, detail: "no tests changed"),
                    Signal(name: "churn", risk: 0.7, weight: 0.3, detail: "160 lines changed")
                ]
            ),
            FileAssessment(
                path: "Sources/Core/Engine.swift",
                riskScore: 48,
                signals: [
                    Signal(name: "churn", risk: 0.75, weight: 0.3, detail: "190 lines changed"),
                    Signal(name: "coupling", risk: 0.3, weight: 0.15, detail: "co-changes with 4 files")
                ]
            ),
            FileAssessment(
                path: "Sources/Core/Formatter.swift",
                riskScore: 14,
                signals: [
                    Signal(name: "churn", risk: 0.2, weight: 0.3, detail: "24 lines changed"),
                    Signal(name: "test-gap", risk: 0.0, weight: 0.2, detail: "tests changed alongside")
                ]
            )
        ]
        let assessment = Assessment(
            scope: "main..HEAD",
            riskScore: 58,
            verdict: .review,
            calibration: Calibration(confidence: 0.65, totalCommits: 320, incidentCommits: 22),
            files: files
        )
        assertSnapshot(MarkdownReporter.render(assessment), "markdown-multi-file")
    }
}
