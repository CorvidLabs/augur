@preconcurrency import Foundation
import XCTest
@testable import AugurKit

internal final class AssessmentJSONTests: XCTestCase {
    internal func testAssessmentJSONCarriesVersionedCompleteContract() throws {
        let assessment = Assessment.empty(scope: "main..HEAD")
        let data = try assessment.jsonData()
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(object["schemaVersion"] as? Int, Assessment.currentSchemaVersion)
        XCTAssertEqual(object["scope"] as? String, "main..HEAD")
        XCTAssertEqual(object["riskScore"] as? Int, 0)
        XCTAssertEqual(object["verdict"] as? String, "proceed")
        XCTAssertNotNil(object["calibration"] as? [String: Any])
        XCTAssertNotNil(object["thresholds"] as? [String: Any])
        XCTAssertEqual((object["files"] as? [Any])?.count, 0)
        XCTAssertEqual((object["excludedPaths"] as? [Any])?.count, 0)
    }

    internal func testLegacyPreVersionedAssessmentStillDecodes() throws {
        let legacy = Data(
            """
            {
              "scope": "working-tree",
              "riskScore": 12,
              "verdict": "proceed",
              "calibration": {"confidence": 0, "totalCommits": 0, "incidentCommits": 0},
              "files": []
            }
            """.utf8
        )

        let assessment = try JSONDecoder().decode(Assessment.self, from: legacy)
        XCTAssertEqual(assessment.schemaVersion, Assessment.currentSchemaVersion)
        XCTAssertEqual(assessment.thresholds, .default)
        XCTAssertTrue(assessment.excludedPaths.isEmpty)
    }

    internal func testEmptyAssessmentRoundTripsDeterministically() throws {
        let original = Assessment.empty(scope: "staged")
        let first = try original.jsonData()
        let decoded = try JSONDecoder().decode(Assessment.self, from: first)
        let second = try decoded.jsonData()

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(second, first)
    }
}
