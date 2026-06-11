@preconcurrency import Foundation
import XCTest
@testable import augur
import AugurKit

/// Tests for `.augur.toml` loading: strict unknown-key rejection (so a typo'd
/// security rule cannot silently fail open) and human-readable decode errors.
final class ConfigTests: XCTestCase {

    // MARK: - Unknown keys are rejected

    /// The original failure mode: `[[sensitivity.rules]]` with `patterns` decodes
    /// to nothing and silently disables the intended rule.
    func testTypoedSensitivityRulesAreRejected() throws {
        let toml = """
        [[sensitivity.rules]]
        label = "billing"
        risk = 0.9
        patterns = ["src/billing"]
        """
        let temp = try TempConfig(toml)
        defer { temp.cleanup() }
        XCTAssertThrowsError(try ConfigLoader.load(explicitPath: temp.path, disabled: false, repoPath: ".")) { error in
            guard case ConfigError.unknownKeys(let path, let details) = error else {
                return XCTFail("expected unknownKeys, got \(error)")
            }
            XCTAssertEqual(path, temp.path)
            XCTAssertTrue(details.contains { $0.contains("sensitivity.rules") }, "\(details)")
            let message = (error as? LocalizedError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("sensitivity.rules"), message)
        }
    }

    func testUnknownTopLevelKeyIsRejected() throws {
        let shape = try ConfigLoader.shape(of: "threshholds = 5\n")
        let unknown = ConfigSchema.unknownKeys(in: shape)
        XCTAssertEqual(unknown.map(\.path), ["threshholds"])
        XCTAssertEqual(unknown.first?.validKeys, ["exclude", "rules", "sensitivity", "thresholds", "weights"])
    }

    func testUnknownNestedKeyIsRejectedWithSiblings() throws {
        let toml = """
        [thresholds]
        review = 30
        bock = 60
        """
        let shape = try ConfigLoader.shape(of: toml)
        let unknown = ConfigSchema.unknownKeys(in: shape)
        XCTAssertEqual(unknown.map(\.path), ["thresholds.bock"])
        XCTAssertEqual(unknown.first?.validKeys, ["block", "review"])
    }

    func testUnknownKeyInsideRuleArrayIsRejectedWithIndex() throws {
        let toml = """
        [[rules]]
        label = "good"
        risk = 0.5
        fragments = ["a"]

        [[rules]]
        label = "bad"
        risk = 0.5
        patterns = ["b"]
        """
        let shape = try ConfigLoader.shape(of: toml)
        let unknown = ConfigSchema.unknownKeys(in: shape)
        XCTAssertEqual(unknown.map(\.path), ["rules[1].patterns"])
    }

    /// Both snake_case and camelCase spellings of known keys are accepted.
    func testSnakeAndCamelCaseKeysAreBothKnown() throws {
        let toml = """
        [weights]
        test_gap = 0.2

        [sensitivity]
        replaceDefaults = true
        """
        let shape = try ConfigLoader.shape(of: toml)
        XCTAssertTrue(ConfigSchema.unknownKeys(in: shape).isEmpty)
    }

    /// A fully valid config still loads after the strictness change.
    func testValidConfigStillLoads() throws {
        let toml = """
        [thresholds]
        review = 30
        block = 60

        [[rules]]
        label = "billing"
        risk = 0.9
        fragments = ["src/billing"]

        [exclude]
        paths = ["vendor/**"]
        """
        let temp = try TempConfig(toml)
        defer { temp.cleanup() }
        let resolved = try ConfigLoader.load(explicitPath: temp.path, disabled: false, repoPath: ".")
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.excludes, ["vendor/**"])
    }

    // MARK: - Decode errors are human-readable

    /// A string where a number belongs must name the key path, not dump the raw
    /// Swift `DecodingError` (which can mention internal types like OffsetDateTime).
    func testWrongTypeErrorNamesTheKeyPath() throws {
        let toml = """
        [thresholds]
        review = "thirty"
        block = 60
        """
        let temp = try TempConfig(toml)
        defer { temp.cleanup() }
        XCTAssertThrowsError(try ConfigLoader.load(explicitPath: temp.path, disabled: false, repoPath: ".")) { error in
            guard case ConfigError.invalid(_, let underlying) = error else {
                return XCTFail("expected ConfigError.invalid, got \(error)")
            }
            XCTAssertTrue(underlying.contains("thresholds.review"), underlying)
            XCTAssertFalse(underlying.contains("OffsetDateTime"), underlying)
        }
    }

    /// A rule missing a required key reports which key is missing.
    func testMissingRequiredKeyIsNamed() throws {
        let toml = """
        [[rules]]
        label = "billing"
        fragments = ["src/billing"]
        """
        let temp = try TempConfig(toml)
        defer { temp.cleanup() }
        XCTAssertThrowsError(try ConfigLoader.load(explicitPath: temp.path, disabled: false, repoPath: ".")) { error in
            guard case ConfigError.invalid(_, let underlying) = error else {
                return XCTFail("expected ConfigError.invalid, got \(error)")
            }
            XCTAssertTrue(underlying.contains("risk"), underlying)
        }
    }

    // MARK: - Coverage CLI resolution

    /// An unusable auto-detected coverage file warns and falls back instead of
    /// failing the whole assessment.
    func testAutoDetectedGarbageCoverageFallsBack() throws {
        let directory = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("augur-clitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let lcov = (directory as NSString).appendingPathComponent("lcov.info")
        try "this is not lcov\n".write(toFile: lcov, atomically: true, encoding: .utf8)

        let options = try CoverageOptions.parse([])
        XCTAssertNil(try options.resolved(repoPath: directory))
    }

    /// An explicit --coverage pointing at garbage is a hard error.
    func testExplicitGarbageCoverageIsAHardError() throws {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("augur-clitest-bad-\(UUID().uuidString).info")
        try "this is not lcov\n".write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }

        let options = try CoverageOptions.parse(["--coverage", path])
        XCTAssertThrowsError(try options.resolved(repoPath: "."))
    }
}

// MARK: - Temp config helper

/// A throwaway `.augur.toml` on disk.
private struct TempConfig {
    let path: String

    init(_ contents: String) throws {
        path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("augur-config-\(UUID().uuidString).toml")
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: path)
    }
}
