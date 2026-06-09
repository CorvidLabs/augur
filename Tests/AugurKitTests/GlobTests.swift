import XCTest
@testable import AugurKit

final class GlobTests: XCTestCase {

    // MARK: - Single star

    func testStarMatchesWithinSegment() {
        let pattern = GlobPattern("*.swift")
        XCTAssertTrue(pattern.matches("Service.swift"))
        XCTAssertTrue(pattern.matches("a.swift"))
        XCTAssertFalse(pattern.matches("Service.kt"))
    }

    func testStarDoesNotCrossSeparator() {
        let pattern = GlobPattern("src/*.swift")
        XCTAssertTrue(pattern.matches("src/Service.swift"))
        XCTAssertFalse(pattern.matches("src/sub/Service.swift"))
    }

    func testStarAnchoredWholePath() {
        let pattern = GlobPattern("vendor")
        XCTAssertTrue(pattern.matches("vendor"))
        XCTAssertFalse(pattern.matches("vendor/x"))
        XCTAssertFalse(pattern.matches("a/vendor"))
    }

    // MARK: - Double star

    func testDoubleStarCrossesSeparators() {
        let pattern = GlobPattern("vendor/**")
        XCTAssertTrue(pattern.matches("vendor/lib/x.swift"))
        XCTAssertTrue(pattern.matches("vendor/a"))
        XCTAssertTrue(pattern.matches("vendor/a/b/c/d.swift"))
        XCTAssertFalse(pattern.matches("src/vendor/x"))
    }

    func testDoubleStarMatchesZeroSegments() {
        // `vendor/**` should also match the bare directory `vendor`.
        let pattern = GlobPattern("vendor/**")
        XCTAssertTrue(pattern.matches("vendor"))
    }

    func testLeadingDoubleStarMatchesAnywhere() {
        let pattern = GlobPattern("**/*.generated.swift")
        XCTAssertTrue(pattern.matches("Sources/App/Model.generated.swift"))
        XCTAssertTrue(pattern.matches("Model.generated.swift"))
        XCTAssertTrue(pattern.matches("a/b/c/X.generated.swift"))
        XCTAssertFalse(pattern.matches("Sources/App/Model.swift"))
    }

    func testNodeModulesDirectoryGlob() {
        let pattern = GlobPattern("node_modules/**")
        XCTAssertTrue(pattern.matches("node_modules/react/index.js"))
        XCTAssertFalse(pattern.matches("src/node_modules_helper.js"))
    }

    // MARK: - Question mark

    func testQuestionMarkSingleCharacter() {
        let pattern = GlobPattern("file?.txt")
        XCTAssertTrue(pattern.matches("file1.txt"))
        XCTAssertTrue(pattern.matches("fileA.txt"))
        XCTAssertFalse(pattern.matches("file.txt"))
        XCTAssertFalse(pattern.matches("file12.txt"))
    }

    // MARK: - Literal / regex-special escaping

    func testDotIsLiteral() {
        let pattern = GlobPattern("a.b")
        XCTAssertTrue(pattern.matches("a.b"))
        XCTAssertFalse(pattern.matches("axb"))
    }

    func testRegexSpecialsAreEscaped() {
        let pattern = GlobPattern("pkg(v1)/x+y.swift")
        XCTAssertTrue(pattern.matches("pkg(v1)/x+y.swift"))
        XCTAssertFalse(pattern.matches("pkgv1/xy.swift"))
    }

    // MARK: - Normalization

    func testNormalizationStripsLeadingDotSlash() {
        let pattern = GlobPattern("src/*.swift")
        XCTAssertTrue(pattern.matches("./src/Service.swift"))
    }

    // MARK: - Lockfile example

    func testLockfileGlob() {
        let pattern = GlobPattern("**/Package.resolved")
        XCTAssertTrue(pattern.matches("Package.resolved"))
        XCTAssertTrue(pattern.matches("a/b/Package.resolved"))
        XCTAssertFalse(pattern.matches("Package.swift"))
    }

    // MARK: - PathFilter

    func testPathFilterExcludesAnyMatch() {
        let filter = PathFilter(globs: ["vendor/**", "**/*.generated.swift"])
        XCTAssertTrue(filter.excludes("vendor/lib/x.swift"))
        XCTAssertTrue(filter.excludes("Sources/App/Model.generated.swift"))
        XCTAssertFalse(filter.excludes("Sources/App/Model.swift"))
    }

    func testEmptyPathFilterExcludesNothing() {
        let filter = PathFilter(globs: [])
        XCTAssertTrue(filter.isEmpty)
        XCTAssertFalse(filter.excludes("anything/at/all.swift"))
    }
}
