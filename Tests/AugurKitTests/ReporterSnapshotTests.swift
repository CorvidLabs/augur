import XCTest
@testable import AugurKit

// MARK: - Reporter Snapshot Tests

/// Golden-file snapshot coverage for the colored terminal `Reporter`.
///
/// Every scenario uses a fully in-code, deterministic `Assessment` (no `Date()`,
/// no git, no wall-clock input feeds the rendered text), so the goldens are
/// stable across runs and machines. Each scenario is snapshotted twice:
/// `color: false` (plain bytes) and `color: true` (raw ANSI escapes stored in
/// the `.snap` file), locking both the layout and the semantic color scheme.
final class ReporterSnapshotTests: XCTestCase {
    // MARK: - Fixtures

    /// A `proceed` assessment: one low-risk, well-tested file.
    private func proceedAssessment() -> Assessment {
        let file = FileAssessment(
            path: "Sources/Core/Formatter.swift",
            riskScore: 12,
            signals: [
                Signal(name: "churn", risk: 0.15, weight: 0.3, detail: "18 lines changed"),
                Signal(name: "test-gap", risk: 0.0, weight: 0.2, detail: "tests changed alongside")
            ]
        )
        return Assessment(
            scope: "main..HEAD",
            riskScore: 12,
            verdict: .proceed,
            calibration: Calibration(confidence: 0.8, totalCommits: 400, incidentCommits: 9),
            files: [file]
        )
    }

    /// A `review` assessment: one moderate-risk file with a churn signal.
    private func reviewAssessment() -> Assessment {
        let file = FileAssessment(
            path: "Sources/Core/Engine.swift",
            riskScore: 50,
            signals: [
                Signal(name: "churn", risk: 0.8, weight: 0.3, detail: "200 lines changed"),
                Signal(name: "test-gap", risk: 0.4, weight: 0.2, detail: "no tests changed")
            ]
        )
        return Assessment(
            scope: "main..HEAD",
            riskScore: 50,
            verdict: .review,
            calibration: Calibration(confidence: 0.5, totalCommits: 100, incidentCommits: 12),
            files: [file]
        )
    }

    /// A `block` assessment: one hot, sensitive file with no tests.
    private func blockAssessment() -> Assessment {
        let file = FileAssessment(
            path: "Sources/Auth/TokenStore.swift",
            riskScore: 82,
            signals: [
                Signal(name: "sensitivity", risk: 1.0, weight: 0.25, detail: "matches auth path"),
                Signal(name: "test-gap", risk: 0.9, weight: 0.2, detail: "no tests changed"),
                Signal(name: "churn", risk: 0.7, weight: 0.3, detail: "160 lines changed")
            ]
        )
        return Assessment(
            scope: "main..HEAD",
            riskScore: 82,
            verdict: .block,
            calibration: Calibration(confidence: 0.7, totalCommits: 250, incidentCommits: 31),
            files: [file]
        )
    }

    /// A multi-file assessment, riskiest-first, for verbose rendering.
    private func multiFileAssessment() -> Assessment {
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
        return Assessment(
            scope: "main..HEAD",
            riskScore: 58,
            verdict: .review,
            calibration: Calibration(confidence: 0.65, totalCommits: 320, incidentCommits: 22),
            files: files
        )
    }

    /// An assessment with excluded paths, to lock the `excluded: N` line.
    private func excludedAssessment() -> Assessment {
        let file = FileAssessment(
            path: "Sources/Core/Engine.swift",
            riskScore: 44,
            signals: [
                Signal(name: "churn", risk: 0.7, weight: 0.3, detail: "150 lines changed"),
                Signal(name: "test-gap", risk: 0.3, weight: 0.2, detail: "no tests changed")
            ]
        )
        return Assessment(
            scope: "main..HEAD",
            riskScore: 44,
            verdict: .review,
            calibration: Calibration(confidence: 0.55, totalCommits: 180, incidentCommits: 14),
            files: [file],
            excludedPaths: [
                "Sources/Generated/Schema.swift",
                "Sources/Generated/Types.swift"
            ]
        )
    }

    // MARK: - Plain (color: false) snapshots

    func testProceedPlainSnapshot() {
        let rendered = Reporter.render(proceedAssessment(), verbose: false, color: false)
        assertSnapshot(rendered, "proceed-plain")
    }

    func testReviewPlainSnapshot() {
        let rendered = Reporter.render(reviewAssessment(), verbose: false, color: false)
        assertSnapshot(rendered, "review-plain")
    }

    func testBlockPlainSnapshot() {
        let rendered = Reporter.render(blockAssessment(), verbose: false, color: false)
        assertSnapshot(rendered, "block-plain")
    }

    func testMultiFileVerbosePlainSnapshot() {
        let rendered = Reporter.render(multiFileAssessment(), verbose: true, color: false)
        assertSnapshot(rendered, "multi-file-verbose-plain")
    }

    func testExcludedPlainSnapshot() {
        let rendered = Reporter.render(excludedAssessment(), verbose: false, color: false)
        assertSnapshot(rendered, "excluded-plain")
    }

    // MARK: - Colored (color: true) snapshots

    func testProceedColorSnapshot() {
        let rendered = Reporter.render(proceedAssessment(), verbose: false, color: true)
        assertSnapshot(rendered, "proceed-color")
    }

    func testReviewColorSnapshot() {
        let rendered = Reporter.render(reviewAssessment(), verbose: false, color: true)
        assertSnapshot(rendered, "review-color")
    }

    func testBlockColorSnapshot() {
        let rendered = Reporter.render(blockAssessment(), verbose: false, color: true)
        assertSnapshot(rendered, "block-color")
    }

    func testMultiFileVerboseColorSnapshot() {
        let rendered = Reporter.render(multiFileAssessment(), verbose: true, color: true)
        assertSnapshot(rendered, "multi-file-verbose-color")
    }

    func testExcludedColorSnapshot() {
        let rendered = Reporter.render(excludedAssessment(), verbose: false, color: true)
        assertSnapshot(rendered, "excluded-color")
    }
}
