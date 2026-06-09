import XCTest
@testable import AugurKit

final class SarifTests: XCTestCase {
    // MARK: - Fixtures

    /// An assessment with one file per verdict band, for level-mapping coverage.
    private func mixedAssessment() -> Assessment {
        let block = FileAssessment(
            path: "src/auth/token.swift",
            riskScore: 80,
            signals: [
                Signal(name: "sensitivity", risk: 0.9, weight: 0.25, detail: "matches sensitive category 'auth'"),
                Signal(name: "test-gap", risk: 0.6, weight: 0.20, detail: "code changed with no test in the changeset"),
            ]
        )
        let review = FileAssessment(
            path: "src/service.swift",
            riskScore: 45,
            signals: [Signal(name: "diff-shape", risk: 0.5, weight: 0.15, detail: "large single-file edit")]
        )
        let proceed = FileAssessment(
            path: "docs/readme.md",
            riskScore: 10,
            signals: [Signal(name: "churn", risk: 0.1, weight: 0.15, detail: "rarely changed")]
        )
        return Assessment(
            scope: "main..HEAD",
            riskScore: 80,
            verdict: .block,
            calibration: Calibration(confidence: 0.8, totalCommits: 500, incidentCommits: 120),
            files: [block, review, proceed]
        )
    }

    // MARK: - Structure

    func testReportHeaderAndDriver() {
        let report = SarifReport(from: mixedAssessment(), toolVersion: "0.2.0")
        XCTAssertEqual(report.version, "2.1.0")
        XCTAssertEqual(report.schema, SarifReport.schemaURL)
        XCTAssertEqual(report.runs.count, 1)
        let driver = report.runs[0].tool.driver
        XCTAssertEqual(driver.name, "augur")
        XCTAssertEqual(driver.semanticVersion, "0.2.0")
        XCTAssertEqual(driver.informationUri, SarifReport.informationURI)
        XCTAssertEqual(driver.rules.count, 1)
        XCTAssertEqual(driver.rules[0].id, SarifReport.ruleID)
    }

    func testOneResultPerFile() {
        let report = SarifReport(from: mixedAssessment(), toolVersion: "0.2.0")
        XCTAssertEqual(report.runs[0].results.count, 3)
        XCTAssertTrue(report.runs[0].results.allSatisfy { $0.ruleId == SarifReport.ruleID })
    }

    // MARK: - Level mapping

    func testVerdictLevelMapping() {
        XCTAssertEqual(SarifReport.Level.from(verdict: .block), .error)
        XCTAssertEqual(SarifReport.Level.from(verdict: .review), .warning)
        XCTAssertEqual(SarifReport.Level.from(verdict: .proceed), .note)
    }

    func testResultLevelsMatchVerdicts() {
        let report = SarifReport(from: mixedAssessment(), toolVersion: "0.2.0")
        let results = report.runs[0].results
        XCTAssertEqual(results[0].level, .error)   // block
        XCTAssertEqual(results[1].level, .warning) // review
        XCTAssertEqual(results[2].level, .note)    // proceed
        XCTAssertEqual(results[0].properties.verdict, "block")
        XCTAssertEqual(results[0].properties.riskScore, 80)
        XCTAssertEqual(results[0].properties.confidence, 20)
    }

    func testLevelHonorsConfiguredThresholds() {
        // A proceed-by-default file becomes block under aggressive thresholds.
        let file = FileAssessment(path: "a.swift", riskScore: 10, signals: [])
        let assessment = Assessment(
            scope: "x",
            riskScore: 10,
            verdict: .block,
            calibration: Calibration(confidence: 0, totalCommits: 0, incidentCommits: 0),
            thresholds: Thresholds(review: 1, block: 2),
            files: [file]
        )
        let report = SarifReport(from: assessment, toolVersion: "0.2.0")
        XCTAssertEqual(report.runs[0].results[0].level, .error)
    }

    // MARK: - Regions

    func testRegionFromFirstAddedLine() {
        let report = SarifReport(
            from: mixedAssessment(),
            toolVersion: "0.2.0",
            addedLinesByPath: ["src/auth/token.swift": [42, 7, 99]]
        )
        let region = report.runs[0].results[0].locations[0].physicalLocation.region
        XCTAssertEqual(region?.startLine, 7) // smallest added line
        XCTAssertEqual(
            report.runs[0].results[0].locations[0].physicalLocation.artifactLocation.uri,
            "src/auth/token.swift"
        )
    }

    func testNoRegionWhenNoAddedLines() {
        let report = SarifReport(from: mixedAssessment(), toolVersion: "0.2.0")
        XCTAssertNil(report.runs[0].results[0].locations[0].physicalLocation.region)
    }

    // MARK: - Message

    func testMessageSummarizesTopSignalsAndScore() {
        let report = SarifReport(from: mixedAssessment(), toolVersion: "0.2.0")
        let text = report.runs[0].results[0].message.text
        XCTAssertTrue(text.contains("block"))
        XCTAssertTrue(text.contains("risk 80/100"))
        XCTAssertTrue(text.contains("auth"), "expected the top signal detail in the message")
    }

    // MARK: - JSON round trip + determinism

    func testJSONRoundTripsAndParses() throws {
        let report = SarifReport(from: mixedAssessment(), toolVersion: "0.2.0")
        let data = try report.jsonData()
        // Parses as valid JSON.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["version"] as? String, "2.1.0")
        XCTAssertNotNil(object?["$schema"])
        // Decodes back to an equal model.
        let decoded = try JSONDecoder().decode(SarifReport.self, from: data)
        XCTAssertEqual(decoded, report)
    }

    func testJSONIsDeterministic() throws {
        let a = try SarifReport(from: mixedAssessment(), toolVersion: "0.2.0").jsonData()
        let b = try SarifReport(from: mixedAssessment(), toolVersion: "0.2.0").jsonData()
        XCTAssertEqual(a, b)
    }

    func testEmptyAssessmentYieldsNoResults() {
        let assessment = Assessment(
            scope: "main..HEAD",
            riskScore: 0,
            verdict: .proceed,
            calibration: Calibration(confidence: 0, totalCommits: 0, incidentCommits: 0),
            files: []
        )
        let report = SarifReport(from: assessment, toolVersion: "0.2.0")
        XCTAssertTrue(report.runs[0].results.isEmpty)
        XCTAssertEqual(report.runs[0].tool.driver.rules.count, 1)
    }
}
