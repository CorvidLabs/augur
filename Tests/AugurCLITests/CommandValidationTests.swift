@preconcurrency import Foundation
import XCTest
import ArgumentParser
@testable import augur

/// Parse-time validation of the CLI surface: conflicting scope flags and the
/// gate threshold are rejected at parse time (usage exit, code 64), instead of
/// silently preferring one flag or printing the generic root usage.
final class CommandValidationTests: XCTestCase {

    // MARK: - Conflicting scope flags

    /// `--staged` plus `--range` used to silently assess the range; now it is a
    /// usage error.
    func testStagedAndRangeTogetherAreRejected() {
        XCTAssertThrowsError(try AugurCommand.parseAsRoot(["check", "--staged", "--range", "HEAD~1..HEAD"])) { error in
            XCTAssertEqual(AugurCommand.exitCode(for: error).rawValue, 64)
            let message = AugurCommand.message(for: error)
            XCTAssertTrue(message.contains("mutually exclusive"), message)
        }
    }

    func testGateRejectsConflictingScopeFlagsToo() {
        XCTAssertThrowsError(try AugurCommand.parseAsRoot(["gate", "--staged", "--range", "HEAD~1..HEAD"])) { error in
            XCTAssertEqual(AugurCommand.exitCode(for: error).rawValue, 64)
        }
    }

    func testSingleScopeFlagsStillParse() throws {
        _ = try AugurCommand.parseAsRoot(["check", "--staged"])
        _ = try AugurCommand.parseAsRoot(["check", "--range", "HEAD~1..HEAD"])
        _ = try AugurCommand.parseAsRoot(["check"])
    }

    // MARK: - Gate threshold

    /// An invalid threshold is a parse-time validation error, so the printed
    /// usage is gate's own (`augur gate ...`), not the generic root usage.
    func testInvalidGateThresholdFailsAtParseTimeWithGateUsage() {
        XCTAssertThrowsError(try AugurCommand.parseAsRoot(["gate", "--threshold", "bananas"])) { error in
            XCTAssertEqual(AugurCommand.exitCode(for: error).rawValue, 64)
            let message = AugurCommand.message(for: error)
            XCTAssertTrue(message.contains("proceed, review, block"), message)
            let full = AugurCommand.fullMessage(for: error)
            XCTAssertTrue(full.contains("gate"), "usage must be gate's own, got: \(full)")
        }
    }

    func testValidGateThresholdParses() throws {
        _ = try AugurCommand.parseAsRoot(["gate", "--threshold", "block"])
    }
}
