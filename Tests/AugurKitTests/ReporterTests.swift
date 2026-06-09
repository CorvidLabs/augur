import XCTest
@testable import AugurKit

/// Tests for the human-readable `Reporter` and its ANSI colorization.
///
/// The plain (`color: false`) output is locked byte-for-byte so adding color
/// never regresses scripted / piped consumers, and the colored output is
/// asserted to carry the right semantic escape codes per verdict.
final class ReporterTests: XCTestCase {
    /// The ANSI escape introducer.
    private let esc = "\u{001B}"

    // MARK: - Fixtures

    private func assessment(verdict: Verdict, riskScore: Double, fileRisk: Double) -> Assessment {
        let file = FileAssessment(
            path: "Sources/Core/Engine.swift",
            riskScore: fileRisk,
            signals: [
                Signal(name: "churn", risk: 0.8, weight: 0.3, detail: "200 lines changed"),
                Signal(name: "tests", risk: 0.0, weight: 0.2, detail: "covered")
            ]
        )
        return Assessment(
            scope: "main..HEAD",
            riskScore: riskScore,
            verdict: verdict,
            calibration: Calibration(confidence: 0.5, totalCommits: 100, incidentCommits: 12),
            files: [file]
        )
    }

    // MARK: - Plain output is unchanged

    /// Locks the exact plain output so color work can never alter it.
    func testPlainOutputIsByteIdentical() {
        let assessment = self.assessment(verdict: .review, riskScore: 50, fileRisk: 50)
        let expected = """
        augur · main..HEAD

          verdict     [!] REVIEW
          risk        [##########          ]  50/100
          confidence  50/100
          calibration weak (12 incidents / 100 commits)

          files (1), riskiest first:
            !    50  Sources/Core/Engine.swift
                  · churn: 200 lines changed

          → an agent should request human review before merging
        """
        XCTAssertEqual(Reporter.render(assessment, verbose: false, color: false), expected)
    }

    /// The two-arg overload must equal the three-arg `color: false` form.
    func testDefaultOverloadEqualsPlain() {
        let assessment = self.assessment(verdict: .block, riskScore: 80, fileRisk: 80)
        XCTAssertEqual(
            Reporter.render(assessment, verbose: true),
            Reporter.render(assessment, verbose: true, color: false)
        )
    }

    /// Plain output never contains an ANSI escape, including verbose mode.
    func testPlainHasNoEscapes() {
        for verdict in Verdict.allCases {
            let assessment = self.assessment(verdict: verdict, riskScore: 50, fileRisk: 50)
            XCTAssertFalse(Reporter.render(assessment, verbose: true, color: false).contains(esc))
        }
    }

    // MARK: - Colored output

    /// Colored output contains escapes and a reset.
    func testColoredOutputContainsEscapes() {
        let assessment = self.assessment(verdict: .review, riskScore: 50, fileRisk: 50)
        let rendered = Reporter.render(assessment, verbose: false, color: true)
        XCTAssertTrue(rendered.contains(esc))
        XCTAssertTrue(rendered.contains(ANSI.reset))
    }

    /// proceed → green (32) on the verdict word.
    func testProceedVerdictIsGreen() {
        let assessment = self.assessment(verdict: .proceed, riskScore: 10, fileRisk: 10)
        let rendered = Reporter.render(assessment, verbose: false, color: true)
        XCTAssertTrue(rendered.contains("\(esc)[32mPROCEED\(esc)[0m"))
    }

    /// review → yellow (33) on the verdict word.
    func testReviewVerdictIsYellow() {
        let assessment = self.assessment(verdict: .review, riskScore: 50, fileRisk: 50)
        let rendered = Reporter.render(assessment, verbose: false, color: true)
        XCTAssertTrue(rendered.contains("\(esc)[33mREVIEW\(esc)[0m"))
    }

    /// block → bold red (1;31) on the verdict word.
    func testBlockVerdictIsBoldRed() {
        let assessment = self.assessment(verdict: .block, riskScore: 80, fileRisk: 80)
        let rendered = Reporter.render(assessment, verbose: false, color: true)
        XCTAssertTrue(rendered.contains("\(esc)[1;31mBLOCK\(esc)[0m"))
    }

    /// File paths are colored cyan (36).
    func testFilePathIsCyan() {
        let assessment = self.assessment(verdict: .review, riskScore: 50, fileRisk: 50)
        let rendered = Reporter.render(assessment, verbose: false, color: true)
        XCTAssertTrue(rendered.contains("\(esc)[36mSources/Core/Engine.swift\(esc)[0m"))
    }

    /// The risk meter uses the gradient block glyphs when colored.
    func testColoredMeterUsesBlockGlyphs() {
        let assessment = self.assessment(verdict: .review, riskScore: 50, fileRisk: 50)
        let rendered = Reporter.render(assessment, verbose: false, color: true)
        XCTAssertTrue(rendered.contains("█"))
        XCTAssertTrue(rendered.contains("░"))
    }

    // MARK: - Colorizer

    /// A disabled colorizer is an identity no-op.
    func testColorizerDisabledIsNoOp() {
        let colorizer = Colorizer(enabled: false)
        XCTAssertEqual(colorizer.apply("hello", Palette.block), "hello")
    }

    /// An enabled colorizer wraps text in the style's codes.
    func testColorizerEnabledWraps() {
        let colorizer = Colorizer(enabled: true)
        XCTAssertEqual(colorizer.apply("hi", ANSI.Style(.green)), "\(esc)[32mhi\(esc)[0m")
    }

    /// A style with multiple attributes joins parameters with `;`.
    func testStyleCombinesAttributes() {
        XCTAssertEqual(ANSI.Style(.bold, .red).apply(to: "x"), "\(esc)[1;31mx\(esc)[0m")
    }
}
